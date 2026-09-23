import Darwin

// Immediate Doppler flicks. The sign is radial, so the user can invert the
// screen mapping without providing labeled examples. Never infer finger count.
public struct ImmediateWave {
    private var quietSince: Double?
    private var armed = false
    private var started: Double?
    private var lastSample = -Double.infinity
    private var cooldownUntil = 0.0
    private var balanceSum = 0.0
    private var votes = 0
    public init() {}
    public mutating func feed(_ r: Reading, now: Double) -> String? {
        if now-lastSample > 0.2 { self = ImmediateWave() }
        lastSample = now
        guard !r.direction.contains("Calibrating"), r.snr > 15 else {
            armed = false; quietSince = nil; started = nil; votes = 0; balanceSum = 0; return nil
        }
        guard now >= cooldownUntil else { return nil }
        // Match Analyzer's minimum reflected-motion strength. Lower-level
        // fluctuations must not become swipes after the analyzer rejects them.
        let moving = r.strength > 0.0003
        if !moving {
            // Separate interrupted candidates without re-arming a completed swipe.
            started = nil; votes = 0; balanceSum = 0
            if quietSince == nil { quietSince = now }
            if now-(quietSince ?? now) >= 0.22 {
                armed = true; started = nil; votes = 0; balanceSum = 0
            }
            return nil
        }
        quietSince = nil
        guard armed else { return nil }
        if started == nil { started = now }
        var balance = 0.0
        if r.waveBands.count == 8 {
            let power = r.waveBands.map { expm1(min(20,max(0,$0))) }
            let away = power.prefix(4).reduce(0,+), toward = power.suffix(4).reduce(0,+)
            balance = (toward-away)/max(1e-9,toward+away)
        } else {
            balance = r.direction == "APPROACHING" ? 1 : r.direction == "MOVING AWAY" ? -1 : 0
        }
        // Use the first coherent lobe of a sweep; the opposite return is ignored.
        if abs(balance) > 0.16 {
            // A sweep's clear lobe must not compete with an earlier opposite twitch.
            if votes > 0 && balance * balanceSum < 0 {
                started = now; votes = 0; balanceSum = 0
            }
            balanceSum += balance; votes += 1
        } else {
            started = now; votes = 0; balanceSum = 0
        }
        let elapsed = now-(started ?? now)
        if elapsed > 0.65 {
            armed = false; started = nil; votes = 0; balanceSum = 0; return nil
        }
        guard elapsed >= 0.04, votes >= 3, abs(balanceSum)/Double(votes) > (1.7 - 1) / (1.7 + 1) else { return nil }
        let event = balanceSum > 0 ? "next" : "previous"
        armed = false; started = nil; votes = 0; balanceSum = 0; cooldownUntil = now+0.65
        return event
    }
}
