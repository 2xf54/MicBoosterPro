import Foundation
import AVFoundation

class AudioEngineManager: ObservableObject {
    private let engine = AVAudioEngine()
    private let intermediateMixer = AVAudioMixerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 2)
    private var isEnginePrepared = false

    @Published var isRunning: Bool = false
    @Published var volumePercent: Int = 73 // 0 to 100
    @Published var errorMessage: String? = nil

    init() {
        // Prepare audio session immediately
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

        // Attach nodes only ONCE
        engine.attach(intermediateMixer)
        engine.attach(eqNode)

        // Connect inputNode -> intermediateMixer -> eqNode -> mainMixerNode
        engine.connect(inputNode, to: intermediateMixer, format: inFormat)
        let mixFormat = intermediateMixer.outputFormat(forBus: 0)
        engine.connect(intermediateMixer, to: eqNode, format: mixFormat)
        engine.connect(eqNode, to: engine.mainMixerNode, format: mixFormat)

        // EQ filter settings
        let hp = eqNode.bands[0]
        hp.filterType = .highPass
        hp.frequency = 100.0
        hp.bypass = false

        let mid = eqNode.bands[1]
        mid.filterType = .parametric
        mid.frequency = 2000.0
        mid.bandwidth = 1.8
        mid.bypass = false

        updateGains()
        engine.prepare()
        isEnginePrepared = true
    }

    func updateGains() {
        let normalized = Float(volumePercent) / 100.0
        let gainDb = (normalized * 32.0) - 2.0
        eqNode.globalGain = gainDb

        intermediateMixer.outputVolume = 1.0
        engine.mainMixerNode.outputVolume = 1.0
    }

    func toggle() {
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
}
