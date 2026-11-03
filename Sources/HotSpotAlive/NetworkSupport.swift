import Foundation
import Darwin
import Network
import SystemConfiguration

enum InterfaceTraffic {
    static func read(_ name: String) -> TrafficSample? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let entry = item.pointee
            guard String(cString: entry.ifa_name) == name,
                  entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_UP) != 0,
                  let raw = entry.ifa_data else { continue }
            let counters = raw.assumingMemoryBound(to: if_data.self).pointee
            return TrafficSample(received: UInt64(counters.ifi_ibytes), sent: UInt64(counters.ifi_obytes))
        }
        return nil
    }

    static func signature(_ name: String) -> String {
        guard let store = SCDynamicStoreCreate(nil, "HotSpotAlive" as CFString, nil, nil),
              let values = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(name)/IPv4" as CFString) as? [String: Any]
        else { return name }
        return name + ":" + ((values["Addresses"] as? [String]) ?? []).joined(separator: ",")
    }

    static func router(_ name: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "HotSpotAlive" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String]
        else { return nil }
        for key in keys {
            if let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
               value["InterfaceName"] as? String == name,
               let router = value["Router"] as? String { return router }
        }
        return nil
    }
}

// All callbacks run on the main queue. One datagram per attempt; no retry loop.
final class TinyHeartbeat {
    private var connection: NWConnection?
    private var timeout: DispatchWorkItem?
    private var completion: ((Bool, Int, Int) -> Void)?
    private var sentBytes = 0

    var isRunning: Bool { connection != nil }

    func start(interface: NWInterface, server: String, completion: @escaping (Bool, Int, Int) -> Void) {
        cancel()
        self.completion = completion
        sentBytes = 0
        let id = UInt16.random(in: .min ... .max)
        let payload = DNSTinyQuery.make(id: id)
        let parameters = NWParameters.udp
        parameters.requiredInterface = interface
        let connection = NWConnection(host: NWEndpoint.Host(server), port: 53, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection else { return }
            switch state {
            case .ready:
                connection.stateUpdateHandler = nil
                connection.send(content: payload, completion: .contentProcessed { [weak self, weak connection] error in
                    guard let self, let connection, self.connection === connection else { return }
                    guard error == nil else { self.finish(success: false); return }
                    self.sentBytes = payload.count + 28 // IPv4 + UDP; excludes link/carrier overhead.
                    connection.receiveMessage { [weak self, weak connection] data, _, _, error in
                        guard let self, let connection, self.connection === connection else { return }
                        let valid = error == nil && data.map { DNSTinyQuery.isReply($0, id: id) } == true
                        self.finish(success: valid, received: data.map { $0.count + 28 } ?? 0)
                    }
                })
            case .failed, .cancelled:
                self.finish(success: false)
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in self?.finish(success: false) }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        connection.start(queue: .main)
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        let old = connection
        connection = nil
        old?.stateUpdateHandler = nil
        old?.cancel()
        completion = nil
    }

    private func finish(success: Bool, received: Int = 0) {
        let callback = completion
        let sent = sentBytes
        cancel()
        callback?(success, sent, received)
    }
}
