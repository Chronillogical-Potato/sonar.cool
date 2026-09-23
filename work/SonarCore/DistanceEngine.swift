import Accelerate

// Short windowed chirps, separated by silence. One speaker avoids mixing two
// different source-to-hand paths. Direct arrival is the timing reference so
// independent input/output device clocks do not require host-time alignment.
public enum RangePulse {
    public static let duration = 0.006
    public static let period = 0.060
    public static let low = 18000.0
    public static let high = 21000.0
    public static func window(_ t:Double) -> Double {
        let edge=min(t,duration-t)
        return edge < 0.0003 ? 0.5-0.5*cos(Double.pi*max(0,edge)/0.0003) : 1
    }
    public static func sample(_ time: Double, descending: Bool = false) -> Double {
        let t = time.truncatingRemainder(dividingBy:period)
        guard t >= 0, t < duration else { return 0 }
        let start = descending ? high : low
        let sweep = descending ? low-high : high-low
        let phase = 2*Double.pi*(start*t+sweep*t*t/(2*duration))
        return sin(phase)*window(t)
    }
}
public struct RangeReading {
    public var profile: [Double]
    public var cm: Double?
    public var quality: Double
    public var status: String
    public var candidate: Double? = nil
    public var calibrating = false
    public var calibrationRemaining: Double? = nil
    public init(profile: [Double], cm: Double?, quality: Double, status: String,
                candidate: Double? = nil, calibrating: Bool = false, calibrationRemaining: Double? = nil) {
        self.profile = profile; self.cm = cm; self.quality = quality; self.status = status
        self.candidate = candidate; self.calibrating = calibrating
        self.calibrationRemaining = calibrationRemaining
    }
}
public final class RangeAnalyzer {
    public let n = 16384
    public let rate: Double
    public let hop: Int
    private let forward: vDSP_DFT_Setup
    private let backward: vDSP_DFT_Setup
    private var refR: [Float]
    private var refI: [Float]
    private var baseline = [Double](repeating:0,count:61)
    private var squares = [Double](repeating:0,count:61)
    private var count = 0
    private var previous: Double?
    private var stable = 0
    public init(rate: Double, descending: Bool = false) {
        self.rate=rate; hop=Int(rate*RangePulse.period)
        forward=vDSP_DFT_zop_CreateSetup(nil,16384,.FORWARD)!
        backward=vDSP_DFT_zop_CreateSetup(nil,16384,.INVERSE)!
        var r=[Float](repeating:0,count:n), i=r
        for k in 0..<Int(rate*RangePulse.duration) {
            let t=Double(k)/rate
            let start=descending ? RangePulse.high : RangePulse.low
            let sweep=descending ? RangePulse.low-RangePulse.high : RangePulse.high-RangePulse.low
            let phase=2*Double.pi*(start*t+sweep*t*t/(2*RangePulse.duration))
            let w=RangePulse.window(t)
            r[k]=Float(sin(phase)*w); i[k]=Float(-cos(phase)*w)
        }
        refR=r; refI=i
        vDSP_DFT_Execute(forward,r,i,&refR,&refI)
    }
    deinit { vDSP_DFT_DestroySetup(forward); vDSP_DFT_DestroySetup(backward) }
    public func analyze(_ input: [Float]) -> RangeReading {
        guard input.count == n else {
            stable=0; previous=nil
            return RangeReading(profile:[],cm:nil,quality:0,status:"Incomplete audio frame · waiting for the next sample")
        }
        let zero=[Float](repeating:0,count:n)
        var r=zero, i=zero
        vDSP_DFT_Execute(forward,input,zero,&r,&i)
        for k in 0..<n {
            let a=r[k], b=i[k]
            r[k]=a*refR[k]+b*refI[k]; i[k]=b*refR[k]-a*refI[k]
        }
        var cr=zero, ci=zero
        vDSP_DFT_Execute(backward,r,i,&cr,&ci)
        var magnitude=[Double](repeating:0,count:n)
        for k in 0..<n { let a=Double(cr[k]); let b=Double(ci[k]); magnitude[k]=sqrt(a*a+b*b)/Double(n) }
        // Use only complete chirps with room for all echo lags after them.
        let end=n-Int(rate*(RangePulse.duration+0.006))-1
        let direct=(0..<end).max(by:{ magnitude[$0] < magnitude[$1] }) ?? 0
        let peak=magnitude[direct]
        let noise=magnitude.sorted()[n/2]
        guard peak > max(1e-5,noise*12) else {
            stable=0; previous=nil
            return RangeReading(profile:[],cm:nil,quality:0,status:"No clear direct chirp · check the audio route")
        }
        var profile=[Double](repeating:0,count:61)
        for cm in 0...60 {
            let lag=Double(cm)*0.02/343*rate
            let index=direct+Int(lag.rounded())
            profile[cm]=magnitude[index]/peak
        }
        let warmup=Int(ceil(3/RangePulse.period))
        if count < warmup {
            count += 1
            for k in 0...60 { baseline[k] += profile[k]; squares[k] += profile[k]*profile[k] }
            if count == warmup {
                for k in 0...60 { baseline[k] /= Double(warmup); squares[k] = sqrt(max(0,squares[k]/Double(warmup)-baseline[k]*baseline[k])) }
            }
            return RangeReading(profile:profile,cm:nil,quality:0,status:"Measuring empty desk · keep hands away (\(Int(ceil(Double(warmup-count)*RangePulse.period)))s)",calibrating:true,calibrationRemaining:Double(warmup-count)*RangePulse.period)
        }
        let excess=(0...60).map { max(0,profile[$0]-baseline[$0]) }
        let candidate=(8...55).max(by:{excess[$0] < excess[$1]})!
        let floor=max(0.003,max(squares[candidate]*3,Array(excess[8...60]).sorted()[26]*2))
        let ratio=excess[candidate]/floor
        let second=(8...60).filter { abs($0-candidate)>8 }.map { excess[$0] }.max() ?? 0
        guard ratio > 4, second < excess[candidate]*0.8 else {
            stable=0; previous=nil
            return RangeReading(profile:excess,cm:nil,quality:min(1,ratio/12),status:ratio > 4 ? "Multiple echoes · hold one palm still" : "Waiting for a distinct hand echo",candidate:ratio>1.5 ? Double(candidate) : nil)
        }
        let cm=Double(candidate)
        if let last=previous, abs(last-cm)<=4 { stable += 1 } else { stable=1 }
        previous=cm
        return RangeReading(profile:excess,cm:stable>=3 ? cm : nil,quality:min(1,ratio/12),status:stable>=3 ? "Stable echo · experimental estimate" : "Checking echo stability…",candidate:cm)
    }
}
