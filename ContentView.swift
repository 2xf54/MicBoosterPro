import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioEngineManager()
    @State private var selectedPreset = "Super Hearing (66)"

    let presets: [(String, Float, Bool, Float)] = [
        ("Super Hearing (66)", 66.0, false, 0.0),
        ("Pro Boost (100)", 100.0, true, 40.0),
        ("Overdrive (150)", 150.0, true, 75.0),
        ("MAX BEAST (200)", 200.0, true, 100.0)
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
                        .fill(audioManager.isRunning ? Color(hex: "FFCC00") : Color.gray)
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // MARK: - Super Hearing Yellow Glowing Mic Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        audioManager.toggleEngine()
                    }
                }) {
                    ZStack {
                        // Outer pulse ring
                        Circle()
                            .fill(audioManager.isRunning ? Color(hex: "FFCC00").opacity(0.25) : Color.white.opacity(0.04))
                            .frame(width: 125, height: 125)
                            .scaleEffect(audioManager.isRunning ? 1.08 : 1.0)

                        // Border ring
                        Circle()
                            .stroke(
                                audioManager.isRunning ? Color(hex: "FFCC00") : Color(hex: "FFCC00").opacity(0.4),
                                lineWidth: 3.5
                            )
                            .frame(width: 105, height: 105)

                        // Center content
                        VStack(spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(audioManager.isRunning ? Color(hex: "FFCC00") : Color(hex: "FFCC00").opacity(0.7))

                            Text(audioManager.isRunning ? "شغال (ON)" : "START")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(audioManager.isRunning ? Color(hex: "FFCC00") : .white)
                        }
                    }
                }
                .padding(.bottom, 14)

                // MARK: - Live Monitor Level Bar
                VStack(spacing: 3) {
                    HStack {
                        Text("LIVE MONITOR STATUS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(audioManager.isRunning ? "ACTIVE • سبيكر السماعة شغال" : "STANDBY")
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

                // MARK: - Sliders & Controls Card
                VStack(spacing: 12) {
                    // Main Boost Slider: 1 to 200 (Super Hearing limit is 66)
                    VStack(spacing: 4) {
                        HStack {
                            Text("قوة التضخيم (BOOST)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)

                            if audioManager.boostLevel > 66 {
                                Text("🔥 فوق الحد")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                            }

                            Spacer()

                            Text("\(Int(audioManager.boostLevel)) / 200")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
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
                    VStack(spacing: 4) {
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
                                Text("قوة التشويش والخشونة")
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

                // MARK: - Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESET PROFILES (سيتات)")
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

                // MARK: - Footer
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .foregroundColor(Color(hex: "FFCC00"))
                        .font(.system(size: 10))
                    Text("Super Hearing Mode Active • تشغيل مباشر بدون قيود")
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
