import XCTest
@testable import PowerNAPPlatform

final class NetworkServiceOrderTests: XCTestCase {
    func testListServicesReturnsNonEmptyOnMacOS() throws {
        guard FileManager.default.isExecutableFile(atPath: NetworkServiceOrder.networksetupPath) else {
            throw XCTSkip("networksetup not available")
        }
        let order = NetworkServiceOrder()
        let services = try order.listServices()
        XCTAssertFalse(services.isEmpty, "macOS typically has at least one network service")
        for s in services {
            XCTAssertFalse(s.name.isEmpty)
        }
    }

    func testFindUSBTetherWithiPhoneEntry() {
        let order = NetworkServiceOrder()
        let services = [
            NetworkService(name: "Wi-Fi", enabled: true, hardwarePort: "Wi-Fi", device: "en0"),
            NetworkService(name: "iPhone USB", enabled: true, hardwarePort: "iPhone USB", device: "en5"),
            NetworkService(name: "Ethernet", enabled: true, hardwarePort: "Ethernet", device: "en1")
        ]
        XCTAssertEqual(order.findUSBTether(services), "iPhone USB")
    }

    func testFindUSBTetherReturnsNilWithoutMatch() {
        let order = NetworkServiceOrder()
        let services = [
            NetworkService(name: "Wi-Fi", enabled: true, hardwarePort: "Wi-Fi", device: "en0"),
            NetworkService(name: "Ethernet", enabled: true, hardwarePort: "Ethernet", device: "en1")
        ]
        XCTAssertNil(order.findUSBTether(services))
    }

    func testFindUSBTetherFallsBackToPatterns() {
        let order = NetworkServiceOrder()
        let services = [
            NetworkService(name: "Wi-Fi", enabled: true, hardwarePort: "Wi-Fi", device: "en0"),
            NetworkService(name: "USB Ethernet", enabled: true, hardwarePort: "USB Ethernet", device: "en5")
        ]
        XCTAssertEqual(order.findUSBTether(services), "USB Ethernet")
    }

    func testFindBluetoothPAN() {
        let order = NetworkServiceOrder()
        let services = [
            NetworkService(name: "Wi-Fi", enabled: true, hardwarePort: "Wi-Fi", device: "en0"),
            NetworkService(name: "Bluetooth PAN", enabled: true, hardwarePort: "Bluetooth PAN", device: "en7")
        ]
        XCTAssertEqual(order.findBluetoothPAN(services), "Bluetooth PAN")
    }

    func testFindBluetoothPANReturnsNilWithoutMatch() {
        let order = NetworkServiceOrder()
        let services = [
            NetworkService(name: "Wi-Fi", enabled: true, hardwarePort: "Wi-Fi", device: "en0"),
            NetworkService(name: "iPhone USB", enabled: true, hardwarePort: "iPhone USB", device: "en8")
        ]
        XCTAssertNil(order.findBluetoothPAN(services))
    }

    func testIsWiFiServiceByName() {
        let order = NetworkServiceOrder()
        let wifi = NetworkService(name: "Wi-Fi", enabled: true, hardwarePort: nil, device: nil)
        let airport = NetworkService(name: "AirPort", enabled: true, hardwarePort: nil, device: nil)
        let ethernet = NetworkService(name: "Ethernet", enabled: true, hardwarePort: nil, device: nil)
        XCTAssertTrue(order.isWiFiService(wifi))
        XCTAssertTrue(order.isWiFiService(airport))
        XCTAssertFalse(order.isWiFiService(ethernet))
    }

    func testIsWiFiServiceByHardwarePort() {
        let order = NetworkServiceOrder()
        let service = NetworkService(name: "Foo", enabled: true, hardwarePort: "Wi-Fi", device: "en0")
        XCTAssertTrue(order.isWiFiService(service))
    }

    func testCurrentOrderIsSubsetOfListServices() throws {
        guard FileManager.default.isExecutableFile(atPath: NetworkServiceOrder.networksetupPath) else {
            throw XCTSkip("networksetup not available")
        }
        let order = NetworkServiceOrder()
        let names = Set(try order.listServices().map { $0.name })
        let fromOrder = Set(try order.currentOrder())
        XCTAssertEqual(names, fromOrder)
    }

    func testParseNetworkServiceOrderOutput() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        (1) Thunderbolt Bridge
        (Hardware Port: Thunderbolt Bridge, Device: bridge0)

        (2) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (3) iPhone USB
        (Hardware Port: iPhone USB, Device: en8)
        """
        let order = NetworkServiceOrder()
        XCTAssertEqual(order.parseServiceOrder(output), ["Thunderbolt Bridge", "Wi-Fi", "iPhone USB"])
    }

    func testParseDefaultRouteInterface() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.1.1
          interface: en8
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
        """
        let order = NetworkServiceOrder()
        XCTAssertEqual(order.parseDefaultRouteInterface(output), "en8")
    }
}
