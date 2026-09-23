public struct Reading {
    public var spectrum: [Float]
    public var baseline: [Float]
    public var direction: String
    public var carrierDB: Float
    public var snr: Float
    public var strength: Float
    public var waveBands: [Double] = []
    public var opposedStrength: Float = 0
    public var waveform: [Float] = []
    public var sampleRate: Double = 0
    public var firstFrequency: Double = 0
    public var binWidth: Double = 0
    public var calibrationRemaining: Double? = nil
    public init(spectrum: [Float], baseline: [Float], direction: String, carrierDB: Float,
                snr: Float, strength: Float, waveBands: [Double] = [], opposedStrength: Float = 0,
                waveform: [Float] = [], sampleRate: Double = 0, firstFrequency: Double = 0,
                binWidth: Double = 0, calibrationRemaining: Double? = nil) {
        self.spectrum = spectrum; self.baseline = baseline; self.direction = direction
        self.carrierDB = carrierDB; self.snr = snr; self.strength = strength
        self.waveBands = waveBands; self.opposedStrength = opposedStrength
        self.waveform = waveform; self.sampleRate = sampleRate
        self.firstFrequency = firstFrequency; self.binWidth = binWidth
        self.calibrationRemaining = calibrationRemaining
    }
}
