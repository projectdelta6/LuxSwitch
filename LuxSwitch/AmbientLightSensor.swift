import Foundation
import IOKit
import IOKit.hid

enum AmbientLightSensor {

    private static let sensorUsagePage: UInt32 = 0x20
    private static let illuminanceUsage: UInt32 = 0x04D1

    static func readLux() -> Int? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

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
            guard let elements = IOHIDDeviceCopyMatchingElements(
                device, nil, IOOptionBits(kIOHIDOptionsTypeNone)
            ) as? [IOHIDElement] else {
                continue
            }

            for element in elements {
                let usagePage = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)

                if usagePage == sensorUsagePage && usage == illuminanceUsage {
                    var valueRef: Unmanaged<IOHIDValue> = Unmanaged.passUnretained(
                        unsafeBitCast(0, to: IOHIDValue.self)
                    )
                    guard IOHIDDeviceGetValue(device, element, &valueRef) == kIOReturnSuccess else {
                        continue
                    }
                    return IOHIDValueGetIntegerValue(valueRef.takeUnretainedValue())
                }
            }
        }

        return nil
    }
}
