import Foundation
import AVFoundation

class AudioEngineManager: ObservableObject {
    private let engine = AVAudioEngine()
    private let intermediateMixer = AVAudioMixerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 2)
    private let distortionNode = AVAudioUnitDistortion()
    private let noiseMixer = AVAudioMixerNode()
    private var noiseSourceNode: AVAudioSourceNode?
    private var isEnginePrepared = false

    @Published var isRunning: Bool = false
    @Published var volumePercent: Int = 73 // 0 to 100 (100 = max boost)
    @Published var noisePercent: Int = 0   // 0 to 100 (distortion + static noise)
    @Published var isMonitoringMuted: Bool = false // MIC button: false = Red (hear self), true = Green (muted locally)
    @Published var errorMessage: String? = nil

    init() {
        setupAudioSession()
    }

    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(48000)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Session error: \(error.localizedDescription)")
        }
    }

    private func prepareEngineIfNeeded() {
        guard !isEnginePrepared else { return }

        setupAudioSession()

        let inputNode = engine.inputNode
        let inFormat = inputNode.inputFormat(forBus: 0)

        guard inFormat.sampleRate > 0 else { return }

        // Attach processing nodes once
        engine.attach(intermediateMixer)
        engine.attach(eqNode)
        engine.attach(distortionNode)
        engine.attach(noiseMixer)

        // Connect inputNode -> intermediateMixer -> eqNode -> distortionNode -> mainMixerNode
        engine.connect(inputNode, to: intermediateMixer, format: inFormat)
        let mixFormat = intermediateMixer.outputFormat(forBus: 0)
        engine.connect(intermediateMixer, to: eqNode, format: mixFormat)
        engine.connect(eqNode, to: distortionNode, format: mixFormat)
        engine.connect(distortionNode, to: engine.mainMixerNode, format: mixFormat)

        // Static noise generator node for audible distortion/interference
        let sourceNode = AVAudioSourceNode(format: mixFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = Float.random(in: -0.35...0.35)
                for buffer in ablPointer {
                    if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        data[frame] = sample
                    }
                }
            }
            return noErr
        }
        self.noiseSourceNode = sourceNode
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: noiseMixer, format: mixFormat)
        engine.connect(noiseMixer, to: engine.mainMixerNode, format: mixFormat)

        // EQ filter settings
        let hp = eqNode.bands[0]
        hp.filterType = .highPass
        hp.frequency = 100.0
        hp.bypass = false

        let mid = eqNode.bands[1]
        mid.filterType = .parametric
        mid.frequency = 2000.0
        mid.bandwidth = 1.8
        mid.gain = 0.0
        mid.bypass = false

        // Distortion preset for voice/radio/speaker noise
        distortionNode.loadFactoryPreset(.multiBrokenSpeaker)

        updateGains()
        engine.prepare()
        isEnginePrepared = true
    }

    func updateGains() {
        // 1. Volume Boost (100% = maximum possible amplification)
        if volumePercent <= 0 {
            intermediateMixer.outputVolume = 0.0
            eqNode.globalGain = 0.0
            eqNode.bands[1].gain = 0.0
        } else {
            let normalized = Float(volumePercent) / 100.0
            intermediateMixer.outputVolume = 0.5 + (normalized * 3.5) // Up to 4.0x
            eqNode.globalGain = normalized * 24.0 // Max +24 dB
            eqNode.bands[1].gain = normalized * 18.0 // Up to +18 dB presence boost
        }

        // 2. Noise / Distortion ("تشويش")
        if noisePercent <= 0 {
            distortionNode.bypass = true
            distortionNode.wetDryMix = 0.0
            noiseMixer.outputVolume = 0.0
        } else {
            let n = Float(noisePercent) / 100.0
            distortionNode.bypass = false
            distortionNode.wetDryMix = n * 100.0
            distortionNode.preGain = (n * 24.0) - 6.0
            noiseMixer.outputVolume = n * 0.65
        }

        // 3. Local Monitoring Mute (MIC button: Red = hear self + noise, Green = muted locally)
        engine.mainMixerNode.outputVolume = isMonitoringMuted ? 0.0 : 1.0
    }

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func toggleMonitoringMute() {
        isMonitoringMuted.toggle()
        updateGains()
    }

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self, granted else { return }
            DispatchQueue.main.async {
                self.prepareEngineIfNeeded()
                do {
                    try self.engine.start()
                    self.isRunning = true
                    self.errorMessage = nil
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }

    func stop() {
        engine.pause()
        isRunning = false
    }

    func setVolume(_ val: Int) {
        volumePercent = max(0, min(100, val))
        updateGains()
    }

    func setNoise(_ val: Int) {
        noisePercent = max(0, min(100, val))
        updateGains()
    }
}
