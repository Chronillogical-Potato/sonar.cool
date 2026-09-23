import XCTest
import SonarCore

final class PositionTests: XCTestCase {
    // MARK: - PlanePosition.solve geometry

    func testForwardGeometryRoundTrip() {
        // For known (x, height) compute the expected echo distances, then verify
        // that solve() recovers the original position to within floating-point tolerance.
        let span = 24.0
        let half = span / 2
        for x in [-8.0, 0.0, 8.0] {
            for h in [10.0, 20.0, 30.0] {
                let d = (x * x + h * h).squareRoot()
                let left  = (((x + half) * (x + half) + h * h).squareRoot() + d - half) / 2
                let right = (((x - half) * (x - half) + h * h).squareRoot() + d - half) / 2
                guard let p = PlanePosition.solve(left: left, right: right, span: span) else {
                    XCTFail("solve() returned nil for x=\(x), h=\(h)")
                    continue
                }
                XCTAssertEqual(p.x, x, accuracy: 0.001, "x round-trip failed for (\(x), \(h))")
                XCTAssertEqual(p.height, h, accuracy: 0.001, "height round-trip failed for (\(x), \(h))")
            }
        }
    }

    func testImpossibleGeometryReturnsNil() {
        XCTAssertNil(PlanePosition.solve(left: 55, right: 8, span: 24),
                     "Impossible geometry must return nil")
    }

    func testNonfiniteInputReturnsNil() {
        XCTAssertNil(PlanePosition.solve(left: .nan, right: 20, span: 24),
                     "NaN left must return nil")
        XCTAssertNil(PlanePosition.solve(left: 20, right: .infinity, span: 24),
                     "Inf right must return nil")
        XCTAssertNil(PlanePosition.solve(left: 20, right: 20, span: .nan),
                     "NaN span must return nil")
    }

    func testNegativeOrZeroInputReturnsNil() {
        XCTAssertNil(PlanePosition.solve(left: -1, right: 20, span: 24))
        XCTAssertNil(PlanePosition.solve(left: 0, right: 20, span: 24))
        XCTAssertNil(PlanePosition.solve(left: 20, right: 20, span: 5),
                     "span < 10 must return nil")
    }

    // MARK: - Two-channel chirp separation

    func runStereoTest(rate: Double) {
        let leftAnalyzer  = RangeAnalyzer(rate: rate, descending: false)
        let rightAnalyzer = RangeAnalyzer(rate: rate, descending: true)
        var l = RangeReading(profile: [], cm: nil, quality: 0, status: "")
        var r = l
        for frame in 0..<63 {
            let samples: [Float] = (0..<leftAnalyzer.n).map { k in
                let t = Double(k + frame * leftAnalyzer.hop) / rate - 0.012
                let direct = RangePulse.sample(t)
                    + 0.8 * RangePulse.sample(t - RangePulse.period / 2, descending: true)
                let echoes = frame >= 55
                    ? 0.2  * RangePulse.sample(t - 15 * 0.02 / 343)
                    + 0.16 * RangePulse.sample(t - RangePulse.period / 2 - 25 * 0.02 / 343, descending: true)
                    : 0
                return Float(direct + echoes)
            }
            l = leftAnalyzer.analyze(samples)
            r = rightAnalyzer.analyze(samples)
        }
        XCTAssertNotNil(l.cm, "Left analyzer should detect echo (\(rate) Hz)")
        XCTAssertNotNil(r.cm, "Right analyzer should detect echo (\(rate) Hz)")
        if let lcm = l.cm { XCTAssertEqual(lcm, 15, accuracy: 4, "Left echo at 15 cm (\(rate) Hz)") }
        if let rcm = r.cm { XCTAssertEqual(rcm, 25, accuracy: 4, "Right echo at 25 cm (\(rate) Hz)") }
    }

    func testStereoChirpSeparation48kHz() { runStereoTest(rate: 48000) }
    func testStereoChirpSeparation96kHz() { runStereoTest(rate: 96000) }
}
