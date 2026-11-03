import Foundation

struct TrafficSample: Equatable {
    let received: UInt64
    let sent: UInt64

    func change(since previous: TrafficSample) -> UInt64? {
        // Interface counters can restart after a reconnect (and wrap on older systems).
        guard received >= previous.received, sent >= previous.sent else { return nil }
        let (sum, overflow) = (received - previous.received).addingReportingOverflow(sent - previous.sent)
        return overflow ? nil : sum
    }
}

enum IdleDecision: Equatable {
    case warmingUp, active, waiting, heartbeat, unavailable
}

struct IdlePolicy {
    private var previous: TrafficSample?
    private var lastActivity: TimeInterval?
    private var lastAttempt: TimeInterval?

    mutating func reset() {
        previous = nil
        lastActivity = nil
        lastAttempt = nil
    }

    mutating func sample(_ current: TrafficSample?, now: TimeInterval, interval: TimeInterval) -> IdleDecision {
        guard let current else {
            reset()
            return .unavailable
        }
        defer { previous = current }
        guard let previous, let delta = current.change(since: previous) else {
            lastActivity = now
            lastAttempt = nil
            return .warmingUp
        }
        if delta > 0 {
            lastActivity = now
            return .active
        }
        guard now - (lastActivity ?? now) >= interval,
              lastAttempt.map({ now - $0 >= interval }) ?? true else { return .waiting }
        lastAttempt = now
        return .heartbeat
    }
}

enum HotspotPolicy {
    static func allows(isWiFi: Bool, isExpensive: Bool, router: String?, allowOtherWiFi: Bool) -> Bool {
        isWiFi && (isExpensive || router == "172.20.10.1" || allowOtherWiFi)
    }
}

enum DNSTinyQuery {
    // A single, fixed public domain; no user browsing information is collected.
    static let question: [UInt8] = {
        var bytes: [UInt8] = [7]
        bytes.append(contentsOf: "example".utf8)
        bytes.append(3)
        bytes.append(contentsOf: "com".utf8)
        bytes.append(contentsOf: [0, 0, 1, 0, 1])
        return bytes
    }()

    static func make(id: UInt16) -> Data {
        var data = Data([UInt8(id >> 8), UInt8(id & 0xff), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        data.append(contentsOf: question)
        return data
    }

    static func isReply(_ data: Data, id: UInt16) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 + question.count,
              bytes[0] == UInt8(id >> 8), bytes[1] == UInt8(id & 0xff),
              bytes[2] & 0xfa == 0x80, // response, standard query, not truncated
              bytes[3] & 0x0f == 0,
              bytes[4] == 0, bytes[5] == 1,
              bytes[6] != 0 || bytes[7] != 0 else { return false }
        return Array(bytes[12..<(12 + question.count)]) == question
    }
}
