import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioEngineManager()

    var body: some View {
        ZStack {
            // Dark Teal / Navy background
            LinearGradient(
                colors: [Color(hex: "0b1520"), Color(hex: "070d14"), Color(hex: "03060a")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top mic badge
                ZStack {
                    Circle()
                        .fill(Color(hex: "FF3B30"))
                        .frame(width: 64, height: 64)
                        .shadow(color: Color(hex: "FF3B30").opacity(audio.isRunning ? 0.85 : 0.3), radius: 12)

                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 8)
                .padding(.bottom, 10)

                // Subheader: EQ and MIC buttons
                HStack {
                    // EQ Button
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color(hex: "FF3B30").opacity(0.45), lineWidth: 1.5)
                                .frame(width: 58, height: 58)
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 21))
                                .foregroundColor(Color(hex: "FF3B30"))
                        }
                        Text("EQ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "FF3B30"))
                    }

                    Spacer()

                    // MIC Button (Red = Hear Self, Green = Muted Locally while running)
                    Button(action: {
                        audio.toggleMonitoringMute()
                    }) {
                        let micColor = audio.isMonitoringMuted ? Color(hex: "10b981") : Color(hex: "FF3B30")
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .stroke(micColor.opacity(0.65), lineWidth: 1.5)
                                    .frame(width: 58, height: 58)
                                    .background(
                                        Circle()
                                            .fill(audio.isMonitoringMuted ? micColor.opacity(0.18) : Color.clear)
                                    )
                                Image(systemName: audio.isMonitoringMuted ? "mic.slash.fill" : "headphones")
                                    .font(.system(size: 21))
                                    .foregroundColor(micColor)
                            }
                            Text("MIC")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(micColor)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 10)

                // Main Percentage & Title
                VStack(spacing: 3) {
                    Text("\(audio.volumePercent)%")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(hex: "FF3B30"))

                    Text("VOLUME BOOST")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "FF3B30").opacity(0.85))
                        .tracking(1.5)
                }

                Spacer(minLength: 10)

                // Center Rotary Dial Wheel (Larger to fill vertical space)
                ZStack {
                    // Outer Ring
                    Circle()
                        .stroke(Color(hex: "FF3B30").opacity(0.18), lineWidth: 2)
                        .frame(width: 284, height: 284)

                    // Bottom Arc Progress Ring
                    Circle()
                        .trim(from: 0.12, to: 0.12 + (CGFloat(audio.volumePercent) / 100.0) * 0.26)
                        .stroke(
                            Color(hex: "FF3B30"),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: 284, height: 284)

                    // Inner Dial Wheel Face
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "152334"), Color(hex: "0a121a")],
                                center: .center,
                                startRadius: 12,
                                endRadius: 130
                            )
                        )
                        .frame(width: 256, height: 256)
                        .shadow(color: .black.opacity(0.6), radius: 10)

                    // Top Cone Highlight for 'boost' slice
                    Path { path in
                        path.move(to: CGPoint(x: 128, y: 128))
                        path.addArc(
                            center: CGPoint(x: 128, y: 128),
                            radius: 126,
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
                    .frame(width: 256, height: 256)

                    // Center Knob
                    Circle()
                        .fill(Color(hex: "080e15"))
                        .frame(width: 102, height: 102)
                        .overlay(Circle().stroke(Color(hex: "FF3B30").opacity(0.28), lineWidth: 1.5))
                        .overlay(
                            Text("VOLUME BOOST")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundColor(Color(hex: "FF3B30"))
                                .multilineTextAlignment(.center)
                                .padding(6)
                        )

                    // 6 Icons around the wheel
                    VStack {
                        // Top item: boost
                        VStack(spacing: 3) {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("boost")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "FF3B30"))
                        .padding(.top, 16)

                        Spacer()

                        // Bottom item: tune
                        VStack(spacing: 3) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 16))
                            Text("tune")
                                .font(.system(size: 9.5))
                        }
                        .foregroundColor(Color(hex: "FF3B30").opacity(0.75))
                        .padding(.bottom, 16)
                    }
                    .frame(width: 256, height: 256)

                    HStack {
                        // Left items: presets & ballance
                        VStack(spacing: 46) {
                            VStack(spacing: 3) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 16))
                                Text("presets")
                                    .font(.system(size: 9.5))
                            }
                            VStack(spacing: 3) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 16))
                                Text("ballance")
                                    .font(.system(size: 9.5))
                            }
                        }
                        .foregroundColor(Color(hex: "FF3B30").opacity(0.75))
                        .padding(.leading, 22)

                        Spacer()

                        // Right items: gain & noise
                        VStack(spacing: 46) {
                            VStack(spacing: 3) {
                                Image(systemName: "arrow.up.and.down")
                                    .font(.system(size: 16))
                                Text("gain")
                                    .font(.system(size: 9.5))
                            }
                            VStack(spacing: 3) {
                                Image(systemName: "ear.and.waveform")
                                    .font(.system(size: 16))
                                Text("noise")
                                    .font(.system(size: 9.5))
                            }
                        }
                        .foregroundColor(Color(hex: "FF3B30").opacity(0.75))
                        .padding(.trailing, 22)
                    }
                    .frame(width: 256, height: 256)

                    // 0 on Left, 1 on Right indicators at bottom arc
                    HStack {
                        Text("0")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "FF3B30"))
                            .frame(width: 24, height: 24)
                            .background(Circle().stroke(Color(hex: "FF3B30"), lineWidth: 1.2))
                            .offset(y: 54)

                        Spacer()

                        Text("1")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "FF3B30"))
                            .frame(width: 24, height: 24)
                            .background(Circle().stroke(Color(hex: "FF3B30"), lineWidth: 1.2))
                            .offset(y: 54)
                    }
                    .frame(width: 300)
                }

                Spacer(minLength: 16)

                // Volume Boost Slider Control
                HStack(spacing: 12) {
                    Text("0%")
                        .font(.system(size: 12, weight: .bold))
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "FF3B30"))
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 16)

                // Extra Hearing Slide START / STOP Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        audio.toggle()
                    }
                }) {
                    GeometryReader { geo in
                        let pillWidth: CGFloat = 122
                        let edgePadding: CGFloat = 4
                        let maxOffset = max(edgePadding, geo.size.width - pillWidth - edgePadding)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(hex: "081119"))
                                .overlay(Capsule().stroke(Color(hex: "FF3B30").opacity(0.35), lineWidth: 1.2))
                                .frame(height: 58)

                            HStack {
                                if audio.isRunning {
                                    Text("Slide to STOP")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(hex: "FF3B30").opacity(0.85))
                                        .padding(.leading, 26)
                                    Spacer()
                                } else {
                                    Spacer()
                                    Text("Slide for start session")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(hex: "FF3B30").opacity(0.85))
                                        .padding(.trailing, 26)
                                }
                            }

                            HStack(spacing: 4) {
                                Text(audio.isRunning ? "STOP" : "START")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(.white)
                                Image(systemName: "chevron.right.2")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .frame(width: pillWidth, height: 50)
                            .background(
                                LinearGradient(
                                    colors: audio.isRunning ? [Color(hex: "10b981"), Color(hex: "059669")] : [Color(hex: "ff4757"), Color(hex: "e84118")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: (audio.isRunning ? Color.green : Color.red).opacity(0.45), radius: 6)
                            .offset(x: audio.isRunning ? maxOffset : edgePadding)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: audio.isRunning)
                        }
                    }
                    .frame(height: 58)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
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
