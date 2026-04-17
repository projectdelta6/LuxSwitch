import Foundation
import IOKit
import IOKit.hid

// Private IOHIDEventSystem APIs — required on Apple Silicon where the ALS is
// not exposed on the standard HID Sensors usage page (0x20).
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ attributes: Int64) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

enum AmbientLightSensor {

    // kIOHIDEventTypeAmbientLightSensor
    private static let alsEventType: Int64 = 12
    // IOHIDEventFieldBase(kIOHIDEventTypeAmbientLightSensor) | 0 — the Level field
    private static let alsLevelField: Int32 = 12 << 16

    // HID Sensors usage page (Intel path)
    private static let sensorUsagePage: UInt32 = 0x20
    private static let illuminanceUsage: UInt32 = 0x04D1

    static func readLux() -> Int? {
        if let lux = readViaEventSystem() { return lux }
        if let lux = readViaHID() { return lux }
        return nil
    }

    // MARK: - Apple Silicon: IOHIDEventSystemClient

    private static func readViaEventSystem() -> Int? {
        guard let clientRef = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            return nil
        }
        let client = clientRef.takeRetainedValue()

        guard let servicesRef = IOHIDEventSystemClientCopyServices(client) else {
            return nil
        }
        let services = servicesRef.takeRetainedValue() as [AnyObject]

        for service in services {
            guard let eventRef = IOHIDServiceClientCopyEvent(service, alsEventType, 0, 0) else {
                continue
            }
            let event = eventRef.takeRetainedValue()
            let lux = IOHIDEventGetFloatValue(event, alsLevelField)
            if lux.isFinite && lux >= 0 {
                return Int(lux)
            }
        }
        return nil
    }

    // MARK: - Intel: standard HID Sensors

    private static func readViaHID() -> Int? {
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
