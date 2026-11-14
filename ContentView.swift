import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioEngineManager()
    @State private var selectedPreset = "Super Hearing (66)"

    let presets: [(String, Float, Bool, Float)] = [
        ("Super Hearing (66)", 66.0, false, 0.0),
        ("High (80)", 80.0, false, 0.0),
        ("Max (100)", 100.0, false, 0.0),
        ("Max + Distortion (100)", 100.0, true, 60.0)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "080c14"), Color(hex: "0f172a"), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill.badge.plus")
                        .foregroundColor(Color(hex: "FFCC00"))
                        .font(.system(size: 20, weight: .bold))

                    Text("SUPER BOOSTER PRO")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    Circle()
                        .fill(audioManager.isRunning ? Color(hex: "FFCC00") : Color.gray)
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

                // Super Hearing Yellow Glowing Mic Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        audioManager.toggleEngine()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(audioManager.isRunning ? Color(hex: "FFCC00").opacity(0.25) : Color.white.opacity(0.04))
                            .frame(width: 130, height: 130)
                            .scaleEffect(audioManager.isRunning ? 1.08 : 1.0)

                        Circle()
                            .stroke(
                                audioManager.isRunning ? Color(hex: "FFCC00") : Color(hex: "FFCC00").opacity(0.4),
                                lineWidth: 3.5
                            )
                            .frame(width: 110, height: 110)

                        VStack(spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(audioManager.isRunning ? Color(hex: "FFCC00") : Color(hex: "FFCC00").opacity(0.7))

                            Text(audioManager.isRunning ? "ON" : "START")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(audioManager.isRunning ? Color(hex: "FFCC00") : .white)
                        }
                    }
                }
                .padding(.bottom, 16)

                // Live Monitor Status Bar
                VStack(spacing: 3) {
                    HStack {
                        Text("LIVE MONITOR STATUS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(audioManager.isRunning ? "ACTIVE" : "STANDBY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(audioManager.isRunning ? Color(hex: "FFCC00") : .gray)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [Color(hex: "FFCC00"), .orange, .red], startPoint: .leading, endPoint: .trailing))
                                .frame(width: audioManager.isRunning ? geo.size.width : 0, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: audioManager.isRunning)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                // Sliders Card
                VStack(spacing: 12) {
                    // Main Boost Slider: 1 to 100
                    VStack(spacing: 4) {
                        HStack {
                            Text("BOOST (قوة التضخيم)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)

                            if audioManager.boostLevel > 66 {
                                Text("🔥 فوق حد 66")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                            }

                            Spacer()

                            Text("\(Int(audioManager.boostLevel)) / 100")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundColor(Color(hex: "FFCC00"))
                        }

                        Slider(
                            value: Binding(
                                get: { audioManager.boostLevel },
                                set: { audioManager.setBoost($0) }
                            ),
                            in: 1.0...100.0,
                            step: 1.0
                        )
                        .accentColor(Color(hex: "FFCC00"))
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Smooth Distortion Toggle + Slider
                    VStack(spacing: 4) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { audioManager.isDistortionEnabled },
                                set: { audioManager.setDistortion(enabled: $0, amount: audioManager.distortionAmount) }
                            )) {
                                Text("SMOOTH DISTORTION (تشويش)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .orange))
                        }

                        if audioManager.isDistortionEnabled {
                            HStack {
                                Text("Distortion Amount")
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

                // Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESET PROFILES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(presets, id: \.0) { preset in
                            Button(action: {
                                selectedPreset = preset.0
                                audioManager.boostLevel = preset.1
                                audioManager.isDistortionEnabled = preset.2
                                audioManager.distortionAmount = preset.3
                                audioManager.updateGains()
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(selectedPreset == preset.0 ? Color(hex: "FFCC00") : Color.gray.opacity(0.4))
                                        .frame(width: 5, height: 5)

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

                // Footer
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .foregroundColor(Color(hex: "FFCC00"))
                        .font(.system(size: 10))
                    Text("Super Hearing Engine Active • Live Ear Monitoring")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 8)
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
