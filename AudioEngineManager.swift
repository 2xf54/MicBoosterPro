import Foundation
import AVFoundation
import Accelerate

class AudioEngineManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 2)
    private var isConfigured = false

    @Published var isRunning: Bool = false
    @Published var isMicConnected: Bool = false
    @Published var connectedMicName: String = "غير متصل"
    @Published var preampGain: Float = 12.0      // 1.0x to 30.0x multiplier
    @Published var distortionLevel: Float = 0.45 // 0.0 to 1.0 (Soft saturation / warmth)
    @Published var pierceBoost: Float = 14.0     // High-shelf gain in dB (0 to 24 dB)
    @Published var currentAudioLevel: Float = 0.0 // For live VU meter
    @Published var errorMessage: String? = nil

    init() {
        setupAudioSession()
        checkAudioRoute()
        registerNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Route Changes Listener
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
            // If mic disconnected while running, stop engine to protect hearing and prevent feedback screech
            if !self.isMicConnected && self.isRunning {
                self.stop()
                self.errorMessage = "تم إيقاف التضخيم تلقائياً: تم فصل المايك/السماعة!"
            }
        }
    }

    // MARK: - Detect Headset / External Mic
    func checkAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute

        var hasExternalMicOrHeadset = false
        var deviceName = "مايك الآيفون المدمج (غير مسموح)"

        // Check Input Devices (Wired headset, Bluetooth HFP, USB mic)
        for input in currentRoute.inputs {
            switch input.portType {
            case .headsetMic:
                hasExternalMicOrHeadset = true
                deviceName = "مايك سلكي (Headset Mic)"
            case .bluetoothHFP, .bluetoothLE:
                hasExternalMicOrHeadset = true
                deviceName = input.portName.isEmpty ? "بلوتوث / AirPods" : input.portName
            case .usbAudio:
                hasExternalMicOrHeadset = true
                deviceName = "مايك USB / خارجي"
            default:
                break
            }
        }

        // Also check Outputs (if user plugged headphones/AirPods, input can route through it safely)
        if !hasExternalMicOrHeadset {
            for output in currentRoute.outputs {
                switch output.portType {
                case .headphones:
                    hasExternalMicOrHeadset = true
                    deviceName = "سماعة رأس سلكية"
                case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                    hasExternalMicOrHeadset = true
                    deviceName = output.portName.isEmpty ? "بلوتوث / AirPods" : output.portName
                case .usbAudio:
                    hasExternalMicOrHeadset = true
                    deviceName = "سماعة USB خارجية"
                default:
                    break
                }
            }
        }

        self.isMicConnected = hasExternalMicOrHeadset
        self.connectedMicName = hasExternalMicOrHeadset ? deviceName : "لا يوجد مايك/سماعة متصلة"
    }

    // MARK: - Audio Session Configuration
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

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

        // High Shelf EQ for Pierce effect
        let highShelf = eqNode.bands[0]
        highShelf.filterType = .highShelf
        highShelf.frequency = 3500.0
        highShelf.gain = pierceBoost
        highShelf.bypass = false

        // High Pass filter to cut dead rumbling bass
        let highPass = eqNode.bands[1]
        highPass.filterType = .highPass
        highPass.frequency = 120.0
        highPass.bypass = false

        audioEngine.attach(eqNode)
        audioEngine.connect(inputNode, to: eqNode, format: inputFormat)

        // Install Audio Tap for Gain Multiplier + Soft-Clipping Saturation
        eqNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.processAudioBuffer(buffer: buffer)
        }

        audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: inputFormat)
        isConfigured = true
    }

    // MARK: - Custom DSP
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

                // Step 2: Soft-Clipping Saturation
                if drive > 0.01 {
                    let driven = sample * (1.0 + drive * 4.0)
                    sample = tanh(driven)
                } else {
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
        checkAudioRoute()
        guard isMicConnected else {
            errorMessage = "⚠️ لا يمكنك تشغيل المضخم بدون شبك مايك أو سماعة (سلكي أو بلوتوث / AirPods) لحماية سماعتك من التصفير!"
            return
        }

        setupAudioSession()
        configureEngine()
        do {
            try audioEngine.start()
            isRunning = true
            errorMessage = nil
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
