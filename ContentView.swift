import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioEngineManager()
    @State private var selectedPreset = "Piercing Boost"

    let presets = [
        ("Clean Loud", Float(6.0), Float(0.0), Float(6.0)),
        ("Piercing Boost", Float(12.0), Float(0.4), Float(15.0)),
        ("Overdrive Fuzz", Float(18.0), Float(0.85), Float(12.0)),
        ("MAX CHAOS (+40dB)", Float(28.0), Float(1.0), Float(22.0))
    ]

    var body: some View {
        ZStack {
            // Dark futuristic background
            LinearGradient(colors: [Color(hex: "0b0f19"), Color(hex: "111827"), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                // Top Header
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .foregroundColor(.green)
                            .font(.title2)
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

                // Master Power Button
                Button(action: {
                    withAnimation(.spring()) {
                        audioManager.toggleEngine()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(audioManager.isRunning ? Color.green.opacity(0.2) : Color.red.opacity(0.1))
                            .frame(width: 130, height: 130)
                            .scaleEffect(audioManager.isRunning ? 1.05 + CGFloat(audioManager.currentAudioLevel * 0.15) : 1.0)

                        Circle()
                            .stroke(audioManager.isRunning ? Color.green : Color.red.opacity(0.6), lineWidth: 3)
                            .frame(width: 110, height: 110)

                        VStack(spacing: 6) {
                            Image(systemName: "power")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(audioManager.isRunning ? .green : .red.opacity(0.8))
                            Text(audioManager.isRunning ? "ACTIVE" : "STANDBY")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(audioManager.isRunning ? .green : .gray)
                        }
                    }
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
                                .frame(height: 14)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(audioManager.currentAudioLevel), height: 14)
                                .animation(.linear(duration: 0.08), value: audioManager.currentAudioLevel)
                        }
                    }
                    .frame(height: 14)
                }
                .padding(.horizontal, 24)

                // Sliders Control Center
                VStack(spacing: 16) {
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
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
                .padding(.horizontal, 16)

                // Preset Chips
                VStack(alignment: .leading, spacing: 8) {
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
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
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
                HStack(spacing: 8) {
                    Image(systemName: "bell.and.waveform.fill")
                        .foregroundColor(.green)
                    Text("Background Audio Active • يعمل تلقائياً أثناء مكالمات تيليجرام")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 12)
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
        VStack(alignment: .leading, spacing: 6) {
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
