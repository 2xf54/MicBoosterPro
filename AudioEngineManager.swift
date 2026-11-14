import Foundation
import AVFoundation

class AudioEngineManager: ObservableObject {
    private var engine = AVAudioEngine()
    private var inputMixer = AVAudioMixerNode()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 2)
    private var outputMixer = AVAudioMixerNode()

    @Published var isRunning: Bool = false
    @Published var boostLevel: Float = 66.0 // 1 to 100
    @Published var isDistortionEnabled: Bool = false
    @Published var distortionAmount: Float = 40.0
    @Published var errorMessage: String? = nil

    init() {
        setupSession()
    }

    func setupSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(1024.0 / 48000.0)
            try session.setActive(true)
        } catch {
            print("Session error: \(error.localizedDescription)")
        }
    }

    private func setupEngine() {
        engine.stop()
        engine.reset()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        engine.attach(inputMixer)
        engine.attach(eqNode)
        engine.attach(outputMixer)

        // Dual-mixer chain matching Super Hearing
        engine.connect(inputNode, to: inputMixer, format: inputFormat)
        engine.connect(inputMixer, to: eqNode, format: nil)
        engine.connect(eqNode, to: outputMixer, format: nil)
        engine.connect(outputMixer, to: engine.outputNode, format: nil)

        let lowCut = eqNode.bands[0]
        lowCut.filterType = .highPass
        lowCut.frequency = 100.0
        lowCut.bypass = false

        let voicePresence = eqNode.bands[1]
        voicePresence.filterType = .parametric
        voicePresence.frequency = 2200.0
        voicePresence.bandwidth = 1.5
        voicePresence.bypass = false

        updateGains()
        engine.prepare()
    }

    func updateGains() {
        // Boost level 1 to 100 (where 66 is baseline Super Hearing, 100 is max)
        let gainDb = ((boostLevel / 100.0) * 30.0) - 4.0
        eqNode.globalGain = gainDb

        if isDistortionEnabled {
            let extraDist = (distortionAmount / 100.0) * 12.0
            eqNode.bands[1].gain = extraDist
        } else {
            eqNode.bands[1].gain = 0.0
        }

        inputMixer.outputVolume = 1.0
        outputMixer.outputVolume = 1.0
    }

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func toggleEngine() {
        toggle()
    }

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self, granted else { return }
            DispatchQueue.main.async {
                self.setupSession()
                self.setupEngine()
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
        engine.stop()
        isRunning = false
    }

    func setBoost(_ val: Float) {
        boostLevel = val
        updateGains()
    }

    func setDistortion(enabled: Bool, amount: Float) {
        isDistortionEnabled = enabled
        distortionAmount = amount
        updateGains()
    }
}
