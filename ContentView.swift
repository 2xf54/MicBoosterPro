import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioEngineManager()
    @State private var selectedPreset = "Super Hearing (66)"
    @State private var showAlert = false

    let presets: [(String, Float, Bool, Float, Float)] = [
        ("Super Hearing (66)", 66.0, false, 0.0, 10.0),
        ("Pro Boost (100)", 100.0, true, 30.0, 14.0),
        ("Overdrive (150)", 150.0, true, 65.0, 18.0),
        ("MAX BEAST (200)", 200.0, true, 90.0, 24.0)
    ]

    var body: some View {
        ZStack {
            // Dark audio studio background
            LinearGradient(
                colors: [Color(hex: "080c14"), Color(hex: "0f172a"), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Header
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill.badge.plus")
                        .foregroundColor(Color(hex: "FFCC00"))
                        .font(.system(size: 20, weight: .bold))

                    Text("SUPER BOOSTER PRO")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    // Pulse indicator
                    Circle()
                        .fill(audioManager.isRunning ? Color(hex: "FFCC00") : (audioManager.isMicConnected ? Color.green : Color.red))
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 8)

                // MARK: - Mic Status Pill
                HStack(spacing: 6) {
                    Image(systemName: audioManager.isMicConnected ? "headphones.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(audioManager.isMicConnected ? Color(hex: "00FF66") : .red)

                    Text(audioManager.isMicConnected ? "المايك متصل: \(audioManager.connectedMicName)" : "المايك غير مشبوك: اشبك سماعة للبدء")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(audioManager.isMicConnected ? Color(hex: "00FF66") : .red)
                        .lineLimit(1)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(audioManager.isMicConnected ? Color.green.opacity(0.12) : Color.red.opacity(0.15))
                        .overlay(
                            Capsule().stroke(audioManager.isMicConnected ? Color.green.opacity(0.3) : Color.red.opacity(0.4), lineWidth: 1)
                        )
                )
                .padding(.bottom, 10)

                // MARK: - Super Hearing Yellow Glowing Mic Button
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
                        // Outer pulse ring
                        Circle()
                            .fill(audioManager.isRunning ? Color(hex: "FFCC00").opacity(0.2) : Color.white.opacity(0.04))
                            .frame(width: 115, height: 115)
                            .scaleEffect(audioManager.isRunning ? 1.05 + CGFloat(audioManager.currentAudioLevel * 0.18) : 1.0)

                        // Border ring
                        Circle()
                            .stroke(
                                audioManager.isRunning ? Color(hex: "FFCC00") : (audioManager.isMicConnected ? Color(hex: "FFCC00").opacity(0.5) : Color.red.opacity(0.6)),
                                lineWidth: 3
                            )
                            .frame(width: 98, height: 98)

                        // Center content
                        VStack(spacing: 3) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(audioManager.isRunning ? Color(hex: "FFCC00") : (audioManager.isMicConnected ? Color(hex: "FFCC00").opacity(0.7) : .red.opacity(0.8)))

                            Text(audioManager.isRunning ? "شغال (ON)" : (audioManager.isMicConnected ? "START" : "اشبك السماعة"))
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(audioManager.isRunning ? Color(hex: "FFCC00") : (audioManager.isMicConnected ? .gray : .red))
                        }
                    }
                }
                .alert(isPresented: $showAlert) {
                    Alert(
                        title: Text("⚠️ المايك غير مشبوك"),
                        message: Text("يجب توصيل سماعة رأس أو مايك خارجي (سلكي أو بلوتوث / AirPods) قبل تشغيل التضخيم لتجنب التصفير الحاد."),
                        dismissButton: .default(Text("فهمت، بشبك السماعة"))
                    )
                }
                .padding(.bottom, 8)

                // MARK: - Live VU Level
                VStack(spacing: 3) {
                    HStack {
                        Text("MIC MONITOR LEVEL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(audioManager.currentAudioLevel * 100))%")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(audioManager.currentAudioLevel > 0.85 ? .red : Color(hex: "FFCC00"))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [Color(hex: "FFCC00"), .orange, .red], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(audioManager.currentAudioLevel), height: 6)
                                .animation(.linear(duration: 0.08), value: audioManager.currentAudioLevel)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                // MARK: - Sliders & Controls Card
                VStack(spacing: 10) {
                    // Main Boost Slider: 1 to 200 (Super Hearing limit is 66)
                    VStack(spacing: 3) {
                        HStack {
                            Text("قوة التضخيم (BOOST)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)

                            if audioManager.boostLevel > 66 {
                                Text("🔥 فوق الحد")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                            }

                            Spacer()

                            Text("\(Int(audioManager.boostLevel)) / 200")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundColor(Color(hex: "FFCC00"))
                        }

                        Slider(
                            value: Binding(
                                get: { audioManager.boostLevel },
                                set: { audioManager.setBoost($0) }
                            ),
                            in: 1.0...200.0,
                            step: 1.0
                        )
                        .accentColor(Color(hex: "FFCC00"))
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Smooth Distortion Toggle + Slider
                    VStack(spacing: 3) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { audioManager.isDistortionEnabled },
                                set: { audioManager.setDistortion(enabled: $0, amount: audioManager.distortionAmount) }
                            )) {
                                Text("التشويش السلس (SMOOTH DISTORTION)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .orange))
                        }

                        if audioManager.isDistortionEnabled {
                            HStack {
                                Text("قوة التشويش")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(Int(audioManager.distortionAmount))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }

                            Slider(
                                value: Binding(
                                    get: { audioManager.distortionAmount },
                                    set: { audioManager.setDistortion(enabled: audioManager.isDistortionEnabled, amount: $0) }
                                ),
                                in: 0.0...100.0
                            )
                            .accentColor(.orange)
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Pierce Treble Boost
                    VStack(spacing: 3) {
                        HStack {
                            Text("الحدة والوضوح (PIERCE)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Text("+\(Int(audioManager.treblePierce)) dB")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(.cyan)
                        }

                        Slider(
                            value: Binding(
                                get: { audioManager.treblePierce },
                                set: { audioManager.setPierce($0) }
                            ),
                            in: 0.0...24.0
                        )
                        .accentColor(.cyan)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // MARK: - Presets
                VStack(alignment: .leading, spacing: 5) {
                    Text("PRESET PROFILES (سيتات)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(presets, id: \.0) { preset in
                            Button(action: {
                                selectedPreset = preset.0
                                audioManager.applyPreset(
                                    boost: preset.1,
                                    distEnabled: preset.2,
                                    distAmount: preset.3,
                                    pierce: preset.4
                                )
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(selectedPreset == preset.0 ? Color(hex: "FFCC00") : Color.gray.opacity(0.4))
                                        .frame(width: 5, height: 5)

                                    Text(preset.0)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(selectedPreset == preset.0 ? .white : .gray)
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedPreset == preset.0 ? Color(hex: "FFCC00").opacity(0.2) : Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedPreset == preset.0 ? Color(hex: "FFCC00").opacity(0.6) : Color.clear, lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 4)

                // MARK: - Footer
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .foregroundColor(Color(hex: "FFCC00"))
                        .font(.system(size: 10))
                    Text("Live Ear Monitoring • سبيكر السماعة وسماعات البلوتوث شغال لايف")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 6)
            }
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
