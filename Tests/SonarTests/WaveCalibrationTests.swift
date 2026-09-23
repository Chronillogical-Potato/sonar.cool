import XCTest
import SonarCore

final class WaveCalibrationTests: XCTestCase {
    // 20 ms per synthetic frame — matches the detector's expected real-time cadence.
    private let dt = 0.02

    // Convenience builder for synthetic Doppler frames.
    private func reading(strength: Float, bands: [Double], snr: Float = 40) -> Reading {
        Reading(spectrum: [], baseline: [], direction: "Mixed movement",
                carrierDB: 0, snr: snr, strength: strength, waveBands: bands)
    }

    private func quietReading() -> Reading {
        reading(strength: 0, bands: [Double](repeating: 0, count: 8))
    }

    // Feed `count` quiet frames to arm the detector (requires 220 ms silence).
    private func arm(_ detector: inout ImmediateWave, frames: Int = 12) {
        for frame in 0..<frames {
            _ = detector.feed(quietReading(), now: Double(frame) * dt)
        }
    }

    // MARK: - Rejection tests

    func testWeakSignalRejected() {
        // strength=0.00025 is below the 0.0003 motion threshold.
        for sign in [1.0, -1.0] {
            var detector = ImmediateWave()
            for frame in 0..<60 {
                let active = (20..<28).contains(frame)
                var bands = [Double](repeating: 0, count: 8)
                if active { bands[2] = log1p(1 - sign * 0.6); bands[5] = log1p(1 + sign * 0.6) }
                let r = reading(strength: active ? 0.00025 : 0, bands: bands)
                XCTAssertNil(detector.feed(r, now: Double(frame) * dt),
                             "Weak signal must not produce a swipe (sign \(sign))")
            }
        }
    }

    func testAmbiguousBalanceRejected() {
        // balance=0.25 is below the average-balance threshold (~0.41).
        for sign in [1.0, -1.0] {
            var detector = ImmediateWave()
            for frame in 0..<60 {
                let active = (20..<28).contains(frame)
                var bands = [Double](repeating: 0, count: 8)
                if active { bands[2] = log1p(1 - sign * 0.25); bands[5] = log1p(1 + sign * 0.25) }
                let r = reading(strength: active ? 0.004 : 0, bands: bands)
                XCTAssertNil(detector.feed(r, now: Double(frame) * dt),
                             "Ambiguous balance must not produce a swipe (sign \(sign))")
            }
        }
    }

    func testSymmetricMotionIgnored() {
        var wave = ImmediateWave()
        for frame in 0..<100 {
            let r = reading(strength: frame > 20 ? 0.004 : 0, bands: [1, 1, 1, 1, 1, 1, 1, 1])
            XCTAssertNil(wave.feed(r, now: Double(frame) * dt),
                         "Symmetric motion must not produce a direction")
        }
    }

    // MARK: - Detection tests

    func testNextAndPreviousSwipe() {
        for sign in [1.0, -1.0] {
            var wave = ImmediateWave()
            var events: [String] = []
            for frame in 0..<80 {
                let motion = frame >= 20 && frame < 48
                let value = frame < 33 ? sign : -sign
                var bands = [Double](repeating: 0, count: 8)
                if motion { bands[value > 0 ? 5 : 2] = 2 }
                let r = reading(strength: motion ? 0.004 : 0, bands: bands)
                if let event = wave.feed(r, now: Double(frame) * dt) { events.append(event) }
            }
            XCTAssertEqual(events, [sign > 0 ? "next" : "previous"],
                           "Swipe + return suppression failed (sign \(sign))")
        }
    }

    func testReturnStrokeSuppressedThenRearmed() {
        // A short pause before returning must not re-arm the opposite stroke.
        // A later deliberate gesture still fires after the cooldown expires.
        for sign in [1.0, -1.0] {
            var detector = ImmediateWave()
            var fired: [String] = []
            var times: [Double] = []
            for frame in 0..<120 {
                let t = Double(frame) * dt
                let forward = (0.3..<0.44).contains(t) || (1.6..<1.74).contains(t)
                let returning = (0.70..<0.90).contains(t)
                var bands = [Double](repeating: 0, count: 8)
                if forward { bands[sign > 0 ? 5 : 2] = 2 }
                if returning { bands[sign > 0 ? 2 : 5] = 2 }
                let r = reading(strength: forward || returning ? 0.004 : 0, bands: bands)
                if let event = detector.feed(r, now: t) { fired.append(event); times.append(t) }
            }
            let expected = sign > 0 ? "next" : "previous"
            XCTAssertEqual(fired, [expected, expected],
                           "Return stroke suppression or re-arm failed (sign \(sign))")
            XCTAssertEqual(times.count, 2, "Expected exactly 2 events (sign \(sign))")
            if times.count >= 1 {
                XCTAssertLessThanOrEqual(times[0], 0.38, "Initial response too slow (sign \(sign))")
            }
        }
    }

    func testOppositePrecursorIgnored() {
        // A faint opposite precursor must not cancel a coherent sweep.
        for sign in [1.0, -1.0] {
            var detector = ImmediateWave()
            var fired: [String] = []
            for frame in 0..<40 {
                let active = (20..<26).contains(frame)
                let balance = frame < 22 ? -sign * 0.18 : sign * 0.32
                var bands = [Double](repeating: 0, count: 8)
                if active { bands[2] = log1p(1 - balance); bands[5] = log1p(1 + balance) }
                let r = reading(strength: active ? 0.004 : 0, bands: bands)
                if let event = detector.feed(r, now: Double(frame) * dt) { fired.append(event) }
            }
            XCTAssertEqual(fired, [sign > 0 ? "next" : "previous"],
                           "Opposite precursor cancelled coherent swipe (sign \(sign))")
        }
    }

    // MARK: - Calibrating guard

    func testCalibratingDirectionBlocksDetection() {
        var detector = ImmediateWave()
        // Arm the detector first with quiet frames.
        arm(&detector)
        // Send strong motion frames but with a "Calibrating" direction tag.
        for frame in 12..<20 {
            let r = Reading(spectrum: [], baseline: [], direction: "Calibrating",
                            carrierDB: 0, snr: 40, strength: 0.01,
                            waveBands: [0, 0, 0, 0, 2, 2, 2, 2])
            XCTAssertNil(detector.feed(r, now: Double(frame) * dt),
                         "Calibrating state must block swipe detection")
        }
    }
}
