import Foundation

var checks = 0
func expect(_ result: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard result() else { fatalError("FAIL: \(message)") }
}

let quiet = TrafficSample(received: 100, sent: 200)
var policy = IdlePolicy()
expect(policy.sample(quiet, now: 0, interval: 25) == .warmingUp, "first observation never sends")
expect(policy.sample(quiet, now: 24, interval: 25) == .waiting, "idle threshold respected")
expect(policy.sample(quiet, now: 25, interval: 25) == .heartbeat, "idle triggers heartbeat")
expect(policy.sample(quiet, now: 30, interval: 25) == .waiting, "no rapid retries")
expect(policy.sample(quiet, now: 50, interval: 25) == .heartbeat, "continued idle triggers next heartbeat")
let busy = TrafficSample(received: 101, sent: 200)
expect(policy.sample(busy, now: 55, interval: 25) == .active, "even one received byte suppresses heartbeat")
expect(policy.sample(busy, now: 79, interval: 25) == .waiting, "activity restarts idle window")
expect(policy.sample(busy, now: 80, interval: 25) == .heartbeat, "heartbeat resumes after activity stops")
let upload = TrafficSample(received: 101, sent: 201)
expect(policy.sample(upload, now: 85, interval: 25) == .active, "uploads suppress heartbeat too")
expect(policy.sample(nil, now: 100, interval: 25) == .unavailable, "missing counter suspends work")
expect(policy.sample(upload, now: 125, interval: 25) == .warmingUp, "reconnect starts fresh")
expect(policy.sample(quiet, now: 130, interval: 25) == .warmingUp, "counter reset never underflows")
policy.reset()
expect(policy.sample(quiet, now: 10000, interval: 25) == .warmingUp, "wake does not replay missed heartbeats")
expect(TrafficSample(received: .max, sent: .max).change(since: TrafficSample(received: 0, sent: 0)) == nil,
       "counter sum overflow handled")

expect(HotspotPolicy.allows(isWiFi: true, isExpensive: true, router: nil, allowOtherWiFi: false), "metered hotspot enabled")
expect(HotspotPolicy.allows(isWiFi: true, isExpensive: false, router: "172.20.10.1", allowOtherWiFi: false), "iPhone gateway fallback")
expect(!HotspotPolicy.allows(isWiFi: true, isExpensive: false, router: "192.168.1.1", allowOtherWiFi: false), "home Wi-Fi excluded")
expect(HotspotPolicy.allows(isWiFi: true, isExpensive: false, router: "192.168.1.1", allowOtherWiFi: true), "explicit ordinary Wi-Fi override")
expect(!HotspotPolicy.allows(isWiFi: false, isExpensive: true, router: "172.20.10.1", allowOtherWiFi: true), "non-Wi-Fi never enabled")

let id: UInt16 = 0x1234
let query = DNSTinyQuery.make(id: id)
expect(query.count == 29, "DNS query is only 29 payload bytes")
expect(!DNSTinyQuery.isReply(query, id: id), "query is not treated as reply")
var reply = query
reply[2] = 0x81
reply[3] = 0x80
reply[7] = 1
// Compressed answer: example.com A 93.184.215.14.
reply.append(contentsOf: [0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 93, 184, 215, 14])
expect(DNSTinyQuery.isReply(reply, id: id), "normal answer accepted")
expect(!DNSTinyQuery.isReply(reply, id: 123), "unrelated DNS transaction rejected")
expect(!DNSTinyQuery.isReply(Data(reply.prefix(10)), id: id), "short datagram rejected safely")
var bad = reply
bad[2] |= 2
expect(!DNSTinyQuery.isReply(bad, id: id), "truncated answer rejected")
bad = reply
bad[3] |= 3
expect(!DNSTinyQuery.isReply(bad, id: id), "DNS failure rejected")
bad = reply
bad[13] = 120
expect(!DNSTinyQuery.isReply(bad, id: id), "wrong question rejected")
bad = reply
bad[7] = 0
expect(!DNSTinyQuery.isReply(bad, id: id), "empty answer rejected")

print("PASS: \(checks) checks (idle scheduling, traffic suppression, reconnects, network scope, DNS validation)")
