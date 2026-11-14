import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioEngineManager()

    var body: some View {
        ZStack {
            // Dark Teal / Navy background matching Super Hearing exactly
            LinearGradient(
                colors: [Color(hex: "0b1520"), Color(hex: "070d14"), Color(hex: "03060a")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top half-circle mic badge matching Super Hearing
                ZStack {
                    Circle()
                        .fill(Color(hex: "FF3B30"))
                        .frame(width: 54, height: 54)
                        .shadow(color: Color(hex: "FF3B30").opacity(audio.isRunning ? 0.8 : 0.25), radius: 10)

                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 4)
                .padding(.bottom, 6)

                // Subheader: EQ and MIC buttons
                HStack {
                    // EQ Button
                    VStack(spacing: 3) {
                        ZStack {
                            Circle()
                                .stroke(Color(hex: "FF3B30").opacity(0.4), lineWidth: 1.5)
                                .frame(width: 50, height: 50)
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "FF3B30"))
                        }
                        Text("EQ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "FF3B30"))
                    }

                    Spacer()

                    // MIC Button (Red = Hear Self + Noise, Green = Muted Locally while running)
                    Button(action: {
                        audio.toggleMonitoringMute()
                    }) {
                        let micColor = audio.isMonitoringMuted ? Color(hex: "10b981") : Color(hex: "FF3B30")
                        VStack(spacing: 3) {
                            ZStack {
                                Circle()
                                    .stroke(micColor.opacity(0.6), lineWidth: 1.5)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(audio.isMonitoringMuted ? micColor.opacity(0.18) : Color.clear)
                                    )
                                Image(systemName: audio.isMonitoringMuted ? "mic.slash.fill" : "headphones")
                                    .font(.system(size: 18))
                                    .foregroundColor(micColor)
                            }
                            Text("MIC")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(micColor)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 6)

                // Main Percentage & Title
                VStack(spacing: 2) {
                    Text("\(audio.volumePercent)%")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(hex: "FF3B30"))

                    Text("VOLUME BOOST")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "FF3B30").opacity(0.85))
                        .tracking(1)
                }
                .padding(.bottom, 8)

                // Super Hearing Center Rotary Dial Wheel (With Bottom Arc)
                ZStack {
                    // Outer Ring with Ticks around bottom
                    Circle()
                        .stroke(Color(hex: "FF3B30").opacity(0.18), lineWidth: 2)
                        .frame(width: 236, height: 236)

                    // Bottom Arc Progress Ring (sweeping along the bottom from left to right like original)
                    Circle()
                        .trim(from: 0.12, to: 0.12 + (CGFloat(audio.volumePercent) / 100.0) * 0.26)
                        .stroke(
                            Color(hex: "FF3B30"),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 236, height: 236)

                    // Inner Dial Wheel Face
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "152334"), Color(hex: "0a121a")],
                                center: .center,
                                startRadius: 10,
                                endRadius: 110
                            )
                        )
                        .frame(width: 212, height: 212)
                        .shadow(color: .black.opacity(0.6), radius: 8)

                    // Top Cone Highlight for 'boost' slice
                    Path { path in
                        path.move(to: CGPoint(x: 106, y: 106))
                        path.addArc(
                            center: CGPoint(x: 106, y: 106),
                            radius: 104,
                            startAngle: .degrees(-125),
                            endAngle: .degrees(-55),
                            clockwise: false
                        )
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF3B30").opacity(0.35), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 212, height: 212)

                    // Center Knob
                    Circle()
                        .fill(Color(hex: "080e15"))
                        .frame(width: 86, height: 86)
                        .overlay(Circle().stroke(Color(hex: "FF3B30").opacity(0.25), lineWidth: 1))
                        .overlay(
                            Text("VOLUME BOOST")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundColor(Color(hex: "FF3B30"))
                                .multilineTextAlignment(.center)
                                .padding(4)
                        )

                    // 6 Icons around the wheel (boost, gain, noise, tune, ballance, presets)
                    VStack {
                        // Top item: boost
                        VStack(spacing: 2) {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("boost")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "FF3B30"))
                        .padding(.top, 14)

                        Spacer()

                        // Bottom item: tune
                        VStack(spacing: 2) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 13))
                            Text("tune")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(Color(hex: "FF3B30").opacity(0.75))
                        .padding(.bottom, 14)
                    }
                    .frame(width: 212, height: 212)

                    HStack {
                        // Left items: presets (top-left) & ballance (bottom-left)
                        VStack(spacing: 36) {
                            VStack(spacing: 2) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 13))
                                Text("presets")
                                    .font(.system(size: 8))
                            }
                            VStack(spacing: 2) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 13))
                                Text("ballance")
                                    .font(.system(size: 8))
                            }
                        }
                        .foregroundColor(Color(hex: "FF3B30").opacity(0.75))
                        .padding(.leading, 18)

                        Spacer()

                        // Right items: gain (top-right) & noise (bottom-right)
                        VStack(spacing: 36) {
                            VStack(spacing: 2) {
                                Image(systemName: "arrow.up.and.down")
                                    .font(.system(size: 13))
                                Text("gain")
                                    .font(.system(size: 8))
                            }
                            VStack(spacing: 2) {
                                Image(systemName: "ear.and.waveform")
                                    .font(.system(size: 13))
                                Text("noise")
                                    .font(.system(size: 8))
                            }
                        }
                        .foregroundColor(Color(hex: "FF3B30").opacity(0.75))
                        .padding(.trailing, 18)
                    }
                    .frame(width: 212, height: 212)

                    // 0 on Left, 1 on Right indicators at bottom arc
                    HStack {
                        Text("0")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "FF3B30"))
                            .frame(width: 20, height: 20)
                            .background(Circle().stroke(Color(hex: "FF3B30"), lineWidth: 1))
                            .offset(y: 45)

                        Spacer()

                        Text("1")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "FF3B30"))
                            .frame(width: 20, height: 20)
                            .background(Circle().stroke(Color(hex: "FF3B30"), lineWidth: 1))
                            .offset(y: 45)
                    }
                    .frame(width: 250)
                }
                .padding(.bottom, 12)

                // Volume Boost Slider Control
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Text("0%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)

                        Slider(
                            value: Binding(
                                get: { Double(audio.volumePercent) },
                                set: { audio.setVolume(Int($0)) }
                            ),
                            in: 0...100,
                            step: 1
                        )
                        .accentColor(Color(hex: "FF3B30"))

                        Text("100%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "FF3B30"))
                    }

                    // Noise / Distortion Slider Control
                    VStack(spacing: 2) {
                        HStack {
                            Text("NOISE / DISTORTION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "FF3B30").opacity(0.85))
                            Spacer()
                            Text("\(audio.noisePercent)%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "FF3B30"))
                        }

                        HStack(spacing: 10) {
                            Text("0%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)

                            Slider(
                                value: Binding(
                                    get: { Double(audio.noisePercent) },
                                    set: { audio.setNoise(Int($0)) }
                                ),
                                in: 0...100,
                                step: 1
                            )
                            .accentColor(Color(hex: "FF3B30"))

                            Text("100%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "FF3B30"))
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 10)

                Spacer()

                // Extra Hearing Slide START / STOP Button (Full-width responsive alignment)
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        audio.toggle()
                    }
                }) {
                    GeometryReader { geo in
                        let pillWidth: CGFloat = 115
                        let edgePadding: CGFloat = 4
                        let maxOffset = max(edgePadding, geo.size.width - pillWidth - edgePadding)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(hex: "081119"))
                                .overlay(Capsule().stroke(Color(hex: "FF3B30").opacity(0.3), lineWidth: 1))
                                .frame(height: 54)

                            HStack {
                                if audio.isRunning {
                                    Text("Slide to STOP")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(hex: "FF3B30").opacity(0.8))
                                        .padding(.leading, 24)
                                    Spacer()
                                } else {
                                    Spacer()
                                    Text("Slide for start session")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(hex: "FF3B30").opacity(0.8))
                                        .padding(.trailing, 24)
                                }
                            }

                            HStack(spacing: 4) {
                                Text(audio.isRunning ? "STOP" : "START")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundColor(.white)
                                Image(systemName: "chevron.right.2")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .frame(width: pillWidth, height: 46)
                            .background(
                                LinearGradient(
                                    colors: audio.isRunning ? [Color(hex: "10b981"), Color(hex: "059669")] : [Color(hex: "ff4757"), Color(hex: "e84118")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: (audio.isRunning ? Color.green : Color.red).opacity(0.4), radius: 6)
                            .offset(x: audio.isRunning ? maxOffset : edgePadding)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: audio.isRunning)
                        }
                    }
                    .frame(height: 54)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }
        }
    }
}

// Hex Helper
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
