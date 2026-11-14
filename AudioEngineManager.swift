import Foundation
import AVFoundation

class AudioEngineManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 2)

    @Published var isRunning: Bool = false
    @Published var isMicConnected: Bool = false
    @Published var connectedMicName: String = "سماعة الرأس"

    // Super Hearing Style Controls (1 to 200)
    @Published var boostLevel: Float = 66.0
    @Published var isDistortionEnabled: Bool = false
    @Published var distortionAmount: Float = 50.0
    @Published var currentAudioLevel: Float = 0.5
    @Published var errorMessage: String? = nil

    init() {
        setupAudioSession()
        checkAudioRoute()
        registerNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Route Notifications
    private func registerNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(notification: Notification) {
        DispatchQueue.main.async {
            self.checkAudioRoute()
        }
    }

    // MARK: - Detect Headset / Earphones
    func checkAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute

        var hasExternalRoute = false
        var deviceName = "سماعة الرأس"

        for output in currentRoute.outputs {
            switch output.portType {
            case .headphones:
                hasExternalRoute = true
                deviceName = "سماعة سلكية"
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                hasExternalRoute = true
                deviceName = output.portName.isEmpty ? "سماعة بلوتوث / AirPods" : output.portName
            case .usbAudio:
                hasExternalRoute = true
                deviceName = "سماعة/مايك USB"
            default:
                break
            }
        }

        for input in currentRoute.inputs {
            switch input.portType {
            case .headsetMic:
                hasExternalRoute = true
                deviceName = "مايك سلكي"
            case .bluetoothHFP:
                hasExternalRoute = true
                deviceName = input.portName.isEmpty ? "مايك بلوتوث" : input.portName
            default:
                break
            }
        }

        self.isMicConnected = hasExternalRoute
        self.connectedMicName = hasExternalRoute ? deviceName : "سماعة الرأس"
    }

    // MARK: - Audio Session Setup (Identical to Super Hearing)
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }
        } catch {
            print("AudioSession Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Ultra-Stable Crash-Proof Engine Setup
    private func configureEngine() {
        audioEngine.stop()
        audioEngine.reset()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Ensure valid sample rate to avoid coreaudio exceptions
        guard format.sampleRate > 0 else { return }

        // Configure EQ for amplification
        let boostBand = eqNode.bands[0]
        boostBand.filterType = .parametric
        boostBand.frequency = 1800.0
        boostBand.bandwidth = 2.0
        boostBand.bypass = false

        let pierceBand = eqNode.bands[1]
        pierceBand.filterType = .highShelf
        pierceBand.frequency = 3500.0
        pierceBand.bypass = false

        updateGains()

        audioEngine.attach(eqNode)

        // Clean direct connection matching Super Hearing
        audioEngine.connect(inputNode, to: eqNode, format: format)
        audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: format)

        // Make sure mainMixer volume is full
        audioEngine.mainMixerNode.outputVolume = 1.0
    }

    func updateGains() {
        // Boost level maps from 1 to 200
        // Standard Super Hearing (66) maps to +14 dB
        // Max (200) maps to +24 dB parametric + +18 dB high shelf
        let normalized = boostLevel / 200.0
        let midGain = normalized * 24.0
        let highGain = normalized * 18.0

        if eqNode.bands.count >= 2 {
            eqNode.bands[0].gain = midGain
            eqNode.bands[1].gain = highGain
        }

        // Slight distortion simulation via extreme gain driving
        if isDistortionEnabled {
            let distGain = (distortionAmount / 100.0) * 8.0
            if eqNode.bands.count >= 2 {
                eqNode.bands[0].gain = midGain + distGain
            }
        }
    }

    // MARK: - Start / Stop Actions
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
            errorMessage = nil
            currentAudioLevel = 0.85
        } catch {
            print("Audio Engine Start Failed: \(error.localizedDescription)")
            errorMessage = "تعذر تشغيل الصوت: \(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        audioEngine.stop()
        isRunning = false
        currentAudioLevel = 0.0
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
