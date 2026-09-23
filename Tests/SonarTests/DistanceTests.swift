import XCTest
import SonarCore

final class DistanceTests: XCTestCase {
    func testChirpWindowEnvelope() {
        // Edges should be zero, middle should be one.
        XCTAssertEqual(RangePulse.window(0), 0, accuracy: 0.01)
        XCTAssertEqual(RangePulse.window(RangePulse.duration), 0, accuracy: 0.01)
        XCTAssertEqual(RangePulse.window(RangePulse.duration / 2), 1.0, accuracy: 1e-9)
    }

    func testChirpSampleOutsidePulseIsZero() {
        // Samples outside [0, duration) within a period must be silent.
        XCTAssertEqual(RangePulse.sample(RangePulse.duration + 0.001), 0)
        XCTAssertEqual(RangePulse.sample(RangePulse.period - 0.001), 0)
    }

    func testChirpSampleInsidePulseIsNonZero() {
        // Centre of the pulse should have amplitude in (0, 1].
        let mid = RangePulse.duration / 2
        XCTAssertGreaterThan(abs(RangePulse.sample(mid)), 0.1)
        XCTAssertGreaterThan(abs(RangePulse.sample(mid, descending: true)), 0.1)
    }

    func testChirpWrapsAcrossPeriod() {
        // sample(t) == sample(t + period) for any t.
        let t = 0.001
        XCTAssertEqual(RangePulse.sample(t), RangePulse.sample(t + RangePulse.period), accuracy: 1e-12)
    }

    // MARK: - RangeAnalyzer end-to-end

    private func makeFrame(analyzer: RangeAnalyzer, echoCm: Double?, frame: Int) -> [Float] {
        let rate = analyzer.rate
        return (0..<analyzer.n).map { k in
            let t = Double(k + frame * analyzer.hop) / rate - 0.012
            let direct = RangePulse.sample(t)
            let echo = echoCm.map { 0.15 * RangePulse.sample(t - $0 * 0.02 / 343) } ?? 0
            return Float(direct + echo)
        }
    }

    func runAnalyzerTests(rate: Double) {
        let analyzer = RangeAnalyzer(rate: rate)

        // Empty input must not crash or report a distance.
        XCTAssertNil(analyzer.analyze([]).cm, "Empty input must not produce distance")

        // Silence must not produce a distance.
        XCTAssertNil(
            analyzer.analyze([Float](repeating: 0, count: analyzer.n)).cm,
            "Silence must not produce distance"
        )

        // Calibration: warmup takes ceil(3 / period) = 50 frames; feed 55 to clear it safely.
        var reading = RangeReading(profile: [], cm: nil, quality: 0, status: "")
        for frame in 0..<55 {
            reading = analyzer.analyze(makeFrame(analyzer: analyzer, echoCm: nil, frame: frame))
        }
        XCTAssertNil(reading.cm, "Static baseline must not produce distance")

        // Echo detection at 10, 20, 30 cm: feed 7 frames (≥ 3 needed for stability lock).
        for expectedCm in [10.0, 20.0, 30.0] {
            for frame in 55..<62 {
                reading = analyzer.analyze(makeFrame(analyzer: analyzer, echoCm: expectedCm, frame: frame))
            }
            XCTAssertNotNil(reading.cm, "Should detect echo at \(expectedCm) cm (\(rate) Hz)")
            if let cm = reading.cm {
                XCTAssertEqual(cm, expectedCm, accuracy: 4,
                               "Echo at \(expectedCm) cm within ±4 cm (\(rate) Hz), got \(cm)")
            }
        }

        // Lost echo: one frame without an echo after stability lock must clear the distance.
        reading = analyzer.analyze(makeFrame(analyzer: analyzer, echoCm: nil, frame: 63))
        XCTAssertNil(reading.cm, "Lost echo must clear distance")
    }

    func testEchoDetection48kHz() { runAnalyzerTests(rate: 48000) }
    func testEchoDetection96kHz() { runAnalyzerTests(rate: 96000) }
}
