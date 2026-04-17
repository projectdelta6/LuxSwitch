import Foundation
import IOKit
import IOKit.hid

enum AmbientLightSensor {

    // HID Sensor Usage Page
    private static let sensorUsagePage: UInt32 = 0x20

    // Element-level data field for illuminance
    private static let illuminanceUsage: UInt32 = 0x04D1

    // Device-level sensor types for ambient light
    private static let ambientLightUsages: Set<UInt32> = [
        0x0041,  // Sensor Type: Ambient Light
        0x04D1,  // Data Field: Light Illuminance
    ]

    static func readLux() -> Int? {
        // Try HID approach (works on both Intel and Apple Silicon)
        if let lux = readViaHID() { return lux }

        // Fallback: try the legacy AppleLMUController (older Intel Macs)
        if let lux = readViaLMU() { return lux }

        return nil
    }

    // MARK: - HID approach

    private static func readViaHID() -> Int? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match all devices on the sensor usage page
        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey as String: sensorUsagePage
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }

        for device in deviceSet {
            // Check if this is an ambient light sensor device
            let primaryUsage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? UInt32 ?? 0
            let isALSDevice = ambientLightUsages.contains(primaryUsage)

            guard let elements = IOHIDDeviceCopyMatchingElements(
                device, nil, IOOptionBits(kIOHIDOptionsTypeNone)
            ) as? [IOHIDElement] else {
                continue
            }

            for element in elements {
                let usagePage = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)

                // Match illuminance data field, or any input element on a known ALS device
                let isIlluminance = usagePage == sensorUsagePage && usage == illuminanceUsage
                let isALSInput = isALSDevice && usagePage == sensorUsagePage &&
                    IOHIDElementGetType(element) == kIOHIDElementTypeInput_Misc

                if isIlluminance || isALSInput {
                    if let value = readElementValue(device: device, element: element) {
                        return value
                    }
                }
            }
        }

        return nil
    }

    private static func readElementValue(device: IOHIDDevice, element: IOHIDElement) -> Int? {
        var valueRef: Unmanaged<IOHIDValue> = Unmanaged.passUnretained(
            unsafeBitCast(0, to: IOHIDValue.self)
        )
        guard IOHIDDeviceGetValue(device, element, &valueRef) == kIOReturnSuccess else {
            return nil
        }
        return IOHIDValueGetIntegerValue(valueRef.takeUnretainedValue())
    }

    // MARK: - Legacy LMU approach (older Intel Macs)

    private static func readViaLMU() -> Int? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleLMUController")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connect) == kIOReturnSuccess else {
            return nil
        }
        defer { IOServiceClose(connect) }

        var outputCount: UInt32 = 2
        var values = [UInt64](repeating: 0, count: 2)
        let result = IOConnectCallMethod(connect, 0, nil, 0, nil, 0, &values, &outputCount, nil, nil)
        guard result == kIOReturnSuccess else { return nil }

        // LMU returns two values (left and right sensor), average them
        let avg = (values[0] + values[1]) / 2
        return Int(avg)
    }
}
