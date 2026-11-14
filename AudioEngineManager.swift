import Foundation
import AVFoundation

class AudioEngineManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 4)
    private var distortionNode = AVAudioUnitDistortion()
    private var boostMixer = AVAudioMixerNode()

    @Published var isRunning: Bool = false
    @Published var isMicConnected: Bool = false
    @Published var connectedMicName: String = "غير متصل"

    // Super Hearing Style Controls
    @Published var boostLevel: Float = 66.0         // 1 to 200 (Super Hearing stops at 66, this reaches 200!)
    @Published var isDistortionEnabled: Bool = true // Toggle smooth distortion on/off
    @Published var distortionAmount: Float = 40.0   // 0% to 100% smooth saturation
    @Published var treblePierce: Float = 14.0       // High shelf pierce boost
    @Published var currentAudioLevel: Float = 0.0   // Live VU meter
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
            if !self.isMicConnected && self.isRunning {
                self.stop()
                self.errorMessage = "تم إيقاف التضخيم تلقائياً: تم فصل السماعة"
            }
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
                deviceName = "سماعة سلكية (Aux/Lightning)"
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
        self.connectedMicName = hasExternalRoute ? deviceName : "غير متصل (اشبك سماعة أولاً)"
    }

    // MARK: - Audio Session Setup
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }
        } catch {
            print("Session error: \(error.localizedDescription)")
        }
    }

    // MARK: - Configure Engine (Crash-Free Multi-Stage Super Hearing DSP)
    private func configureEngine() {
        audioEngine.stop()
        audioEngine.reset()

        let inputNode = audioEngine.inputNode

        // Band 0: High Pass (Cuts muddy bass below 120Hz)
        let hpBand = eqNode.bands[0]
        hpBand.filterType = .highPass
        hpBand.frequency = 120.0
        hpBand.bypass = false

        // Band 1: Mid Boost Stage 1
        let mid1 = eqNode.bands[1]
        mid1.filterType = .parametric
        mid1.frequency = 1500.0
        mid1.bandwidth = 2.0
        mid1.bypass = false

        // Band 2: Mid Boost Stage 2 (Cascaded for extreme 200x boost)
        let mid2 = eqNode.bands[2]
        mid2.filterType = .parametric
        mid2.frequency = 2600.0
        mid2.bandwidth = 1.8
        mid2.bypass = false

        // Band 3: Pierce High-Shelf
        let trebleBand = eqNode.bands[3]
        trebleBand.filterType = .highShelf
        trebleBand.frequency = 3800.0
        trebleBand.bypass = false

        // Configure Built-in Smooth Analog Distortion Unit
        distortionNode.loadFactoryPreset(.multiDistortedFunk)
        distortionNode.preGain = 0.0

        updateDSPParams()

        // Attach all nodes
        audioEngine.attach(eqNode)
        audioEngine.attach(distortionNode)
        audioEngine.attach(boostMixer)

        // Connect safely with format: nil for automatic hardware sample-rate conversion
        audioEngine.connect(inputNode, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: distortionNode, format: nil)
        audioEngine.connect(distortionNode, to: boostMixer, format: nil)
        audioEngine.connect(boostMixer, to: audioEngine.mainMixerNode, format: nil)

        // Install safe VU meter tap
        boostMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] (buffer, time) in
            guard let self = self, let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = channelData[0]
            var sum: Float = 0.0
            for i in 0..<frameLength {
                sum += abs(samples[i])
            }
            let avg = sum / Float(frameLength)
            DispatchQueue.main.async {
                self.currentAudioLevel = min(1.0, avg * 5.0)
            }
        }
    }

    func updateDSPParams() {
        // Map boostLevel (1 to 200) to cascaded gains
        let normalized = boostLevel / 200.0
        let stage1Gain = normalized * 24.0
        let stage2Gain = normalized * 24.0
        let trebleGain = (treblePierce / 24.0) * 16.0 + (normalized * 8.0)

        if eqNode.bands.count >= 4 {
            eqNode.bands[1].gain = stage1Gain
            eqNode.bands[2].gain = stage2Gain
            eqNode.bands[3].gain = trebleGain
        }

        // Smooth Distortion Wet/Dry Mix
        if isDistortionEnabled {
            distortionNode.wetDryMix = min(100.0, distortionAmount)
        } else {
            distortionNode.wetDryMix = 0.0
        }

        let mixerVolume = min(1.0, 0.45 + (normalized * 0.55))
        boostMixer.outputVolume = mixerVolume
    }

    // MARK: - Actions
    func toggleEngine() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        checkAudioRoute()
        guard isMicConnected else {
            errorMessage = "⚠️ يرجى توصيل سماعة أولاً لمنع التصفير الحاد!"
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if granted {
                    self.executeStart()
                } else {
                    self.errorMessage = "يرجى السماح بصلاحية المايكروفون من إعدادات الآيفون."
                }
            }
        }
    }

    private func executeStart() {
        setupAudioSession()
        configureEngine()
        do {
            try audioEngine.start()
            isRunning = true
            errorMessage = nil
        } catch {
            print("Start error: \(error.localizedDescription)")
            errorMessage = "خطأ في تشغيل الصوت: \(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        boostMixer.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
        currentAudioLevel = 0.0
    }

    func setBoost(_ val: Float) {
        boostLevel = val
        updateDSPParams()
    }

    func setDistortion(enabled: Bool, amount: Float) {
        isDistortionEnabled = enabled
        distortionAmount = amount
        updateDSPParams()
    }

    func setPierce(_ val: Float) {
        treblePierce = val
        updateDSPParams()
    }

    func applyPreset(boost: Float, distEnabled: Bool, distAmount: Float, pierce: Float) {
        self.boostLevel = boost
        self.isDistortionEnabled = distEnabled
        self.distortionAmount = distAmount
        self.treblePierce = pierce
        self.updateDSPParams()
    }
}
