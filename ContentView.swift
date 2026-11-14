import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioEngineManager()
    @State private var slideOffset: CGFloat = 0

    let modes = [
        ("boost", "speaker.wave.2.fill"),
        ("gain", "arrow.up.and.down.and.sparkles"),
        ("noise", "ear.and.waveform"),
        ("tune", "person.crop.circle"),
        ("ballance", "arrow.left.arrow.right"),
        ("presets", "square.grid.2x2")
    ]

    var body: some View {
        ZStack {
            // Dark Teal / Navy background matching Super Hearing exactly
            LinearGradient(
                colors: [Color(hex: "0d1824"), Color(hex: "08101a"), Color(hex: "04080e")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Mic Icon in Glowing Circle
                Button(action: {
                    withAnimation { audio.toggle() }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "E5A912"))
                            .frame(width: 62, height: 62)
                            .shadow(color: Color(hex: "E5A912").opacity(audio.isRunning ? 0.6 : 0.2), radius: 12)

                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 12)

                // Subheader: EQ and MIC buttons
                HStack {
                    // EQ Button
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color(hex: "E5A912").opacity(0.4), lineWidth: 1.5)
                                .frame(width: 58, height: 58)
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "E5A912"))
                        }
                        Text("EQ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "E5A912"))
                    }

                    Spacer()

                    // MIC Button
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color(hex: "E5A912").opacity(0.4), lineWidth: 1.5)
                                .frame(width: 58, height: 58)
                            Image(systemName: "headphones")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "E5A912"))
                        }
                        Text("MIC")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "E5A912"))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 14)

                // Main Percentage & Title
                VStack(spacing: 2) {
                    Text("\(audio.volumePercent)%")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(hex: "E5A912"))

                    Text("VOLUME BOOST")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "E5A912").opacity(0.8))
                        .tracking(1)
                }
                .padding(.bottom, 14)

                // Super Hearing Center Rotary Dial Wheel
                ZStack {
                    // Outer Ring with Ticks
                    Circle()
                        .stroke(Color(hex: "E5A912").opacity(0.2), lineWidth: 2)
                        .frame(width: 270, height: 270)

                    // Arc Progress Ring
                    Circle()
                        .trim(from: 0.25, to: 0.25 + (CGFloat(audio.volumePercent) / 100.0) * 0.5)
                        .stroke(
                            Color(hex: "E5A912"),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(90))
                        .frame(width: 270, height: 270)

                    // Inner Dial Wheel Face
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "172638"), Color(hex: "0c1520")],
                                center: .center,
                                startRadius: 10,
                                endRadius: 130
                            )
                        )
                        .frame(width: 240, height: 240)
                        .shadow(color: .black.opacity(0.5), radius: 10)

                    // Active Slice Highlight Cone
                    Path { path in
                        path.move(to: CGPoint(x: 120, y: 120))
                        path.addArc(
                            center: CGPoint(x: 120, y: 120),
                            radius: 115,
                            startAngle: .degrees(-120),
                            endAngle: .degrees(-60),
                            clockwise: false
                        )
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "E5A912").opacity(0.35), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 240, height: 240)

                    // Center Knob
                    Circle()
                        .fill(Color(hex: "091019"))
                        .frame(width: 100, height: 100)
                        .overlay(Circle().stroke(Color(hex: "E5A912").opacity(0.3), lineWidth: 1))
                        .overlay(
                            Text("VOLUME BOOST")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(Color(hex: "E5A912"))
                                .multilineTextAlignment(.center)
                                .padding(6)
                        )

                    // Wheel Icons (boost, gain, noise, tune, ballance, presets)
                    VStack {
                        // Top item: boost
                        VStack(spacing: 2) {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("boost")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "E5A912"))
                        .padding(.top, 22)

                        Spacer()

                        // Bottom item: tune
                        VStack(spacing: 2) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 15))
                            Text("tune")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(Color(hex: "E5A912").opacity(0.7))
                        .padding(.bottom, 22)
                    }
                    .frame(width: 240, height: 240)

                    HStack {
                        // Left item: presets
                        VStack(spacing: 2) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 14))
                            Text("presets")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(Color(hex: "E5A912").opacity(0.7))
                        .padding(.leading, 24)

                        Spacer()

                        // Right item: gain
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 14))
                            Text("gain")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(Color(hex: "E5A912").opacity(0.7))
                        .padding(.trailing, 24)
                    }
                    .frame(width: 240, height: 240)

                    // 0 on Left, 1 on Right indicators
                    HStack {
                        Text("0")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "E5A912"))
                            .frame(width: 22, height: 22)
                            .background(Circle().stroke(Color(hex: "E5A912"), lineWidth: 1))
                            .offset(x: -8)

                        Spacer()

                        Text("1")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "E5A912"))
                            .frame(width: 22, height: 22)
                            .background(Circle().stroke(Color(hex: "E5A912"), lineWidth: 1))
                            .offset(x: 8)
                    }
                    .frame(width: 285)
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let delta = Float(-value.translation.height / 3.0)
                            let newVol = min(100, max(0, audio.volumePercent + Int(delta)))
                            audio.setVolume(newVol)
                        }
                )
                .padding(.bottom, 20)

                // Slider Control to easily slide from 0 to 100
                HStack(spacing: 12) {
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
                    .accentColor(Color(hex: "E5A912"))

                    Text("100%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "E5A912"))
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 22)

                Spacer()

                // Super Hearing Slide / Tap START Button
                Button(action: {
                    withAnimation(.spring()) {
                        audio.toggle()
                    }
                }) {
                    ZStack(alignment: .leading) {
                        // Container Capsule
                        Capsule()
                            .fill(Color(hex: "09121a"))
                            .overlay(Capsule().stroke(Color(hex: "E5A912").opacity(0.3), lineWidth: 1))
                            .frame(height: 58)

                        // Slide Text on the right
                        HStack {
                            Spacer()
                            Text(audio.isRunning ? "Tap to STOP session" : "Slide for start session")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "E5A912").opacity(0.7))
                            Spacer()
                        }
                        .padding(.leading, 80)

                        // Red/Green Pill Knob
                        HStack(spacing: 4) {
                            Text(audio.isRunning ? "STOP" : "START")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.right.2")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(width: 125, height: 50)
                        .background(
                            LinearGradient(
                                colors: audio.isRunning ? [Color(hex: "10b981"), Color(hex: "059669")] : [Color(hex: "ff4757"), Color(hex: "e84118")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: (audio.isRunning ? Color.green : Color.red).opacity(0.4), radius: 6)
                        .padding(.leading, 4)
                        .offset(x: audio.isRunning ? 180 : 0)
                        .animation(.spring(), value: audio.isRunning)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
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
