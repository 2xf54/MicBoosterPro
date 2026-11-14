import Foundation
import AVFoundation
import Accelerate

class AudioEngineManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 2)
    private var isConfigured = false

    @Published var isRunning: Bool = false
    @Published var preampGain: Float = 5.0       // 1.0x to 30.0x multiplier
    @Published var distortionLevel: Float = 0.35 // 0.0 to 1.0 (Soft saturation / warmth)
    @Published var pierceBoost: Float = 12.0     // High-shelf gain in dB (0 to 24 dB)
    @Published var currentAudioLevel: Float = 0.0 // For live VU meter

    init() {
        setupAudioSession()
    }

    // MARK: - Audio Session Configuration
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Set hardware input gain to 100% maximum if device hardware supports it
            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }
        } catch {
            print("Audio Session Setup Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Audio Engine Configuration
    private func configureEngine() {
        audioEngine.stop()
        audioEngine.reset()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            print("Invalid input format")
            return
        }

        // Configure High Shelf EQ for Pierce effect
        let highShelf = eqNode.bands[0]
        highShelf.filterType = .highShelf
        highShelf.frequency = 3500.0 // 3.5 kHz presence
        highShelf.gain = pierceBoost
        highShelf.bypass = false

        // Configure High Pass to remove sub-bass rumble
        let highPass = eqNode.bands[1]
        highPass.filterType = .highPass
        highPass.frequency = 120.0
        highPass.bypass = false

        audioEngine.attach(eqNode)
        audioEngine.connect(inputNode, to: eqNode, format: inputFormat)

        // Install Audio Tap for Custom Digital Boost + Saturation (Overdrive)
        eqNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.processAudioBuffer(buffer: buffer)
        }

        // Connect EQ to mainMixer
        audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: inputFormat)
        isConfigured = true
    }

    // MARK: - Custom DSP: Preamp Gain Multiplier + Soft-Clipping Saturation
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        let gain = self.preampGain
        let drive = self.distortionLevel

        var peakLevel: Float = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]

            for i in 0..<frameLength {
                var sample = samples[i]

                // Step 1: Preamp amplification
                sample *= gain

                // Step 2: Soft-Clipping Saturation (Warm analog distortion curve)
                if drive > 0.01 {
                    let driven = sample * (1.0 + drive * 4.0)
                    // Hyperbolic tangent soft saturation curve: tanh(x)
                    sample = tanh(driven)
                } else {
                    // Fast safety limiter if distortion is off
                    sample = max(-1.0, min(1.0, sample))
                }

                samples[i] = sample

                let absVal = abs(sample)
                if absVal > peakLevel {
                    peakLevel = absVal
                }
            }
        }

        DispatchQueue.main.async {
            self.currentAudioLevel = min(1.0, peakLevel)
        }
    }

    // MARK: - User Actions
    func toggleEngine() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        setupAudioSession()
        configureEngine()
        do {
            try audioEngine.start()
            isRunning = true
        } catch {
            print("Failed to start audio engine: \(error.localizedDescription)")
            isRunning = false
        }
    }

    func stop() {
        if isConfigured {
            eqNode.removeTap(onBus: 0)
        }
        audioEngine.stop()
        isRunning = false
        currentAudioLevel = 0.0
    }

    func updateEQ(gain: Float) {
        pierceBoost = gain
        if eqNode.bands.count > 0 {
            eqNode.bands[0].gain = gain
        }
    }

    func applyPreset(gain: Float, dist: Float, pierce: Float) {
        self.preampGain = gain
        self.distortionLevel = dist
        self.updateEQ(gain: pierce)
    }
}
