import Foundation
import Network
import Darwin

let monitor = NWPathMonitor()
let probe = TinyHeartbeat()
var started = false
monitor.pathUpdateHandler = { path in
    DispatchQueue.main.async {
        guard !started else { return }
        started = true
        guard path.status == .satisfied, path.usesInterfaceType(.wifi),
              let interface = path.availableInterfaces.first(where: { $0.type == .wifi }) else {
            print("SKIP: no active Wi-Fi path")
            exit(77)
        }
        let router = InterfaceTraffic.router(interface.name)
        print("interface=\(interface.name), expensive=\(path.isExpensive), router=\(router ?? "unknown")")
        guard let traffic = InterfaceTraffic.read(interface.name) else {
            print("FAIL: cannot read interface counters")
            exit(1)
        }
        print("counters: received=\(traffic.received), sent=\(traffic.sent)")
        print("identity=\(InterfaceTraffic.signature(interface.name))")
        probe.start(interface: interface, server: "223.5.5.5") { success, sent, received in
            print("DNS heartbeat: success=\(success), sent≈\(sent) bytes, received≈\(received) bytes")
            monitor.cancel()
            exit(success ? 0 : 1)
        }
    }
}
monitor.start(queue: DispatchQueue(label: "HotSpotAlive.test"))
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    print("FAIL: network test timed out")
    exit(1)
}
dispatchMain()
