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
            // Background
            LinearGradient(
                colors: [Color(hex: "080c14"), Color(hex: "0f172a"), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Header
                HStack(spacing: 8) {
                    Image(systemName: "waveform.badge.mic")
                        .foregroundColor(.green)
                        .font(.system(size: 20, weight: .bold))

                    Text("MIC BOOSTER PRO")
                        .font(.system(size: 19, weight: .black, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    // Mini status dot
                    Circle()
                        .fill(audioManager.isRunning ? Color.green : (audioManager.isMicConnected ? Color.yellow : Color.red))
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)

                // MARK: - Mic Status Pill
                HStack(spacing: 8) {
                    Image(systemName: audioManager.isMicConnected ? "headphones.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(audioManager.isMicConnected ? .green : .red)

                    Text(audioManager.isMicConnected ? "المايك متصل: \(audioManager.connectedMicName)" : "المايك غير مشبوك: اشبك سماعة للبدء")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(audioManager.isMicConnected ? .green : .red)
                        .lineLimit(1)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(
                    Capsule()
                        .fill(audioManager.isMicConnected ? Color.green.opacity(0.12) : Color.red.opacity(0.15))
                        .overlay(
                            Capsule().stroke(audioManager.isMicConnected ? Color.green.opacity(0.3) : Color.red.opacity(0.4), lineWidth: 1)
                        )
                )
                .padding(.bottom, 12)

                // MARK: - Power Button
                Button(action: {
                    if !audioManager.isMicConnected {
                        showAlert = true
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            audioManager.toggleEngine()
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(audioManager.isRunning ? Color.green.opacity(0.18) : (audioManager.isMicConnected ? Color.white.opacity(0.04) : Color.red.opacity(0.08)))
                            .frame(width: 105, height: 105)
                            .scaleEffect(audioManager.isRunning ? 1.04 + CGFloat(audioManager.currentAudioLevel * 0.12) : 1.0)

                        Circle()
                            .stroke(
                                audioManager.isRunning ? Color.green : (audioManager.isMicConnected ? Color.gray.opacity(0.4) : Color.red.opacity(0.5)),
                                lineWidth: 2.5
                            )
                            .frame(width: 92, height: 92)

                        VStack(spacing: 4) {
                            Image(systemName: audioManager.isRunning ? "power" : (audioManager.isMicConnected ? "power" : "cable.connector.slash"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(audioManager.isRunning ? .green : (audioManager.isMicConnected ? .white : .red.opacity(0.85)))

                            Text(audioManager.isRunning ? "ACTIVE" : (audioManager.isMicConnected ? "START" : "اشبك المايك"))
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(audioManager.isRunning ? .green : (audioManager.isMicConnected ? .gray : .red))
                        }
                    }
                }
                .alert(isPresented: $showAlert) {
                    Alert(
                        title: Text("⚠️ المايك غير مشبوك"),
                        message: Text("يجب توصيل سماعة رأس أو مايك خارجي (سلكي أو بلوتوث / AirPods) قبل تشغيل التضخيم لحماية أذنك وسماعاتك من التصفير الحاد."),
                        dismissButton: .default(Text("فهمت، بشبك المايك"))
                    )
                }
                .padding(.bottom, 12)

                // MARK: - Live VU Meter
                VStack(spacing: 4) {
                    HStack {
                        Text("AUDIO OUTPUT LEVEL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(audioManager.currentAudioLevel * 100))%")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(audioManager.currentAudioLevel > 0.85 ? .red : .green)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(audioManager.currentAudioLevel), height: 8)
                                .animation(.linear(duration: 0.08), value: audioManager.currentAudioLevel)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // MARK: - Sliders Card
                VStack(spacing: 12) {
                    // Preamp Gain Slider
                    SliderRow(
                        titleAr: "التضخيم",
                        titleEn: "PREAMP GAIN",
                        valueDisplay: String(format: "%.1fx (+%.0fdB)", audioManager.preampGain, audioManager.preampGain * 1.5),
                        color: .green,
                        value: $audioManager.preampGain,
                        range: 1.0...30.0
                    )

                    // Distortion / Overdrive Slider
                    SliderRow(
                        titleAr: "التشويش والخشونة",
                        titleEn: "OVERDRIVE",
                        valueDisplay: "\(Int(audioManager.distortionLevel * 100))%",
                        color: .orange,
                        value: $audioManager.distortionLevel,
                        range: 0.0...1.0
                    )

                    // Pierce Treble Boost
                    SliderRow(
                        titleAr: "الحدة والاختراق",
                        titleEn: "PIERCE BOOST",
                        valueDisplay: "+\(Int(audioManager.pierceBoost)) dB",
                        color: .cyan,
                        value: Binding(
                            get: { audioManager.pierceBoost },
                            set: { audioManager.updateEQ(gain: $0) }
                        ),
                        range: 0.0...24.0
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // MARK: - Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESET PROFILES (سيتات جاهزة)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 20)

                    // 2x2 Grid of Presets
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(presets, id: \.0) { preset in
                            Button(action: {
                                selectedPreset = preset.0
                                audioManager.applyPreset(gain: preset.1, dist: preset.2, pierce: preset.3)
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(selectedPreset == preset.0 ? Color.green : Color.gray.opacity(0.4))
                                        .frame(width: 6, height: 6)

                                    Text(preset.0)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(selectedPreset == preset.0 ? .white : .gray)
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .padding(.vertical, 9)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedPreset == preset.0 ? Color.green.opacity(0.2) : Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedPreset == preset.0 ? Color.green.opacity(0.6) : Color.clear, lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 6)

                // MARK: - Footer
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text("Background Active • شغال بالخلفية مع التيليجرام")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Slider Row Component
struct SliderRow: View {
    let titleAr: String
    let titleEn: String
    let valueDisplay: String
    let color: Color
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                HStack(spacing: 6) {
                    Text(titleAr)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("(\(titleEn))")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                }

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
