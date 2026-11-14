import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioEngineManager()
    @State private var selectedPreset = "Piercing Boost"
    @State private var showAlert = false

    let presets = [
        ("Clean Loud", Float(6.0), Float(0.0), Float(6.0)),
        ("Piercing Boost", Float(14.0), Float(0.45), Float(15.0)),
        ("Overdrive Fuzz", Float(20.0), Float(0.85), Float(14.0)),
        ("MAX CHAOS (+45dB)", Float(30.0), Float(1.0), Float(24.0))
    ]

    var body: some View {
        ZStack {
            // Dark futuristic background
            LinearGradient(colors: [Color(hex: "0b0f19"), Color(hex: "111827"), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                // Top Header with Icon
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.badge.plus")
                            .foregroundColor(.green)
                            .font(.title)

                        Text("MIC BOOSTER PRO")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    Text("HARDWARE & DSP PREAMP ACCELERATOR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                        .tracking(2)
                }
                .padding(.top, 10)

                // Headset / Mic Connection Status Pill (REQUIRED)
                HStack(spacing: 8) {
                    Circle()
                        .fill(audioManager.isMicConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)

                    Image(systemName: audioManager.isMicConnected ? "headphones" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(audioManager.isMicConnected ? .green : .red)

                    Text(audioManager.isMicConnected ? "المايك المتصل: \(audioManager.connectedMicName)" : "المايك غير متصل: اشبك سماعة أو مايك")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(audioManager.isMicConnected ? .green : .red)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(
                    Capsule()
                        .fill(audioManager.isMicConnected ? Color.green.opacity(0.12) : Color.red.opacity(0.15))
                        .overlay(
                            Capsule().stroke(audioManager.isMicConnected ? Color.green.opacity(0.4) : Color.red.opacity(0.5), lineWidth: 1)
                        )
                )

                // Master Power Button
                Button(action: {
                    if !audioManager.isMicConnected {
                        showAlert = true
                    } else {
                        withAnimation(.spring()) {
                            audioManager.toggleEngine()
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(audioManager.isRunning ? Color.green.opacity(0.2) : (audioManager.isMicConnected ? Color.white.opacity(0.05) : Color.red.opacity(0.1)))
                            .frame(width: 125, height: 125)
                            .scaleEffect(audioManager.isRunning ? 1.05 + CGFloat(audioManager.currentAudioLevel * 0.15) : 1.0)

                        Circle()
                            .stroke(audioManager.isRunning ? Color.green : (audioManager.isMicConnected ? Color.gray.opacity(0.5) : Color.red.opacity(0.6)), lineWidth: 3)
                            .frame(width: 108, height: 108)

                        VStack(spacing: 5) {
                            Image(systemName: audioManager.isRunning ? "power" : (audioManager.isMicConnected ? "power" : "cable.connector.slash"))
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(audioManager.isRunning ? .green : (audioManager.isMicConnected ? .white : .red.opacity(0.8)))

                            Text(audioManager.isRunning ? "ACTIVE" : (audioManager.isMicConnected ? "START" : "اشبك المايك"))
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(audioManager.isRunning ? .green : (audioManager.isMicConnected ? .gray : .red))
                        }
                    }
                }
                .alert(isPresented: $showAlert) {
                    Alert(
                        title: Text("⚠️ المايك غير مشبوك"),
                        message: Text("يجب توصيل سماعة رأس أو مايك خارجي (سلكي أو بلوتوث / AirPods) قبل تشغيل التضخيم لحماية أذنك وسماعاتك من التصفير الحاد (Feedback Screech)."),
                        dismissButton: .default(Text("فهمت، بشبك المايك"))
                    )
                }

                // Live VU Meter
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("AUDIO OUTPUT LEVEL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(audioManager.currentAudioLevel * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(audioManager.currentAudioLevel > 0.85 ? .red : .green)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 12)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(audioManager.currentAudioLevel), height: 12)
                                .animation(.linear(duration: 0.08), value: audioManager.currentAudioLevel)
                        }
                    }
                    .frame(height: 12)
                }
                .padding(.horizontal, 24)

                // Sliders Control Center
                VStack(spacing: 14) {
                    // Preamp Gain Slider
                    SliderRow(title: "PREAMP GAIN (التضخيم)",
                              valueDisplay: String(format: "%.1fx (+%.0fdB)", audioManager.preampGain, audioManager.preampGain * 1.5),
                              color: .green,
                              value: $audioManager.preampGain,
                              range: 1.0...30.0)

                    // Distortion / Overdrive Slider
                    SliderRow(title: "DISTORTION / OVERDRIVE (التشويش)",
                              valueDisplay: "\(Int(audioManager.distortionLevel * 100))%",
                              color: .orange,
                              value: $audioManager.distortionLevel,
                              range: 0.0...1.0)

                    // Pierce Treble Boost
                    SliderRow(title: "PIERCE / HIGH-SHELF (الحدة والوضوح)",
                              valueDisplay: "+\(Int(audioManager.pierceBoost)) dB",
                              color: .cyan,
                              value: Binding(
                                get: { audioManager.pierceBoost },
                                set: { audioManager.updateEQ(gain: $0) }
                              ),
                              range: 0.0...24.0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
                .padding(.horizontal, 16)

                // Preset Chips
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESET PROFILES (سيتات جاهزة)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(presets, id: \.0) { preset in
                                Button(action: {
                                    selectedPreset = preset.0
                                    audioManager.applyPreset(gain: preset.1, dist: preset.2, pierce: preset.3)
                                }) {
                                    Text(preset.0)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(selectedPreset == preset.0 ? .black : .white)
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 13)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedPreset == preset.0 ? Color.green : Color.white.opacity(0.1))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer()

                // Background Mode Notice
                HStack(spacing: 6) {
                    Image(systemName: "bell.and.waveform.fill")
                        .foregroundColor(.green)
                    Text("Background Audio Active • يعمل تلقائياً أثناء مكالمات تيليجرام")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Reusable Slider Row
struct SliderRow: View {
    let title: String
    let valueDisplay: String
    let color: Color
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(valueDisplay)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(color)
            }

            Slider(value: $value, in: range)
                .accentColor(color)
        }
    }
}

// MARK: - Hex Color Helper
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
