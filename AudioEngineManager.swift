import Foundation
import AVFoundation

class AudioEngineManager: ObservableObject {
    private var engine = AVAudioEngine()
    private var intermediateMixer = AVAudioMixerNode()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 2)

    @Published var isRunning: Bool = false
    @Published var boostLevel: Float = 66.0 // 1 to 100
    @Published var isDistortionEnabled: Bool = false
    @Published var distortionAmount: Float = 40.0
    @Published var errorMessage: String? = nil

    init() {
        setupAudioSession()
    }

    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Session error: \(error.localizedDescription)")
        }
    }

    private func setupEngine() {
        engine.stop()
        engine.reset()

        let inputNode = engine.inputNode
        let inFormat = inputNode.inputFormat(forBus: 0)

        // Attach nodes
        engine.attach(intermediateMixer)
        engine.attach(eqNode)

        // 1. Connect inputNode to intermediateMixer (Mixer automatically handles any mono/sample rate)
        engine.connect(inputNode, to: intermediateMixer, format: inFormat)

        // 2. Connect intermediateMixer to EQ using clean standard mixer output format
        let mixFormat = intermediateMixer.outputFormat(forBus: 0)
        engine.connect(intermediateMixer, to: eqNode, format: mixFormat)

        // 3. Connect EQ to mainMixerNode (mainMixerNode connects automatically to outputNode)
        engine.connect(eqNode, to: engine.mainMixerNode, format: mixFormat)

        // Setup EQ filters
        let hp = eqNode.bands[0]
        hp.filterType = .highPass
        hp.frequency = 120.0
        hp.bypass = false

        let mid = eqNode.bands[1]
        mid.filterType = .parametric
        mid.frequency = 2000.0
        mid.bandwidth = 1.8
        mid.bypass = false

        updateGains()
        engine.prepare()
    }

    func updateGains() {
        // Boost level 1 to 100: Level 66 = +18dB, Level 100 = +32dB
        let normalized = boostLevel / 100.0
        let gainDb = (normalized * 32.0) - 2.0
        eqNode.globalGain = gainDb

        if isDistortionEnabled {
            let distGain = (distortionAmount / 100.0) * 12.0
            eqNode.bands[1].gain = distGain
        } else {
            eqNode.bands[1].gain = 0.0
        }

        intermediateMixer.outputVolume = 1.0
        engine.mainMixerNode.outputVolume = 1.0
    }

    func toggleEngine() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self, granted else { return }
            DispatchQueue.main.async {
                self.setupAudioSession()
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
