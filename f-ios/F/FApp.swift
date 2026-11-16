import SwiftUI
import UIKit

@main
struct FApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @State private var isLit = false
    @State private var isPressed = false

    private let bgColor = Color(red: 14 / 255, green: 14 / 255, blue: 18 / 255)
    private let offFill = Color(red: 27 / 255, green: 27 / 255, blue: 34 / 255)
    private let offStroke = Color(red: 50 / 255, green: 50 / 255, blue: 62 / 255)
    private let offText = Color(red: 148 / 255, green: 148 / 255, blue: 168 / 255)

    private let redCore = Color(red: 255 / 255, green: 42 / 255, blue: 59 / 255)
    private let redDeep = Color(red: 195 / 255, green: 16 / 255, blue: 34 / 255)
    private let redRim = Color(red: 255 / 255, green: 120 / 255, blue: 132 / 255)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            // Ambient red glow behind the circle when lit
            Circle()
                .fill(redCore.opacity(isLit ? 0.32 : 0.0))
                .frame(width: 340, height: 340)
                .blur(radius: 45)
                .animation(.easeInOut(duration: 0.25), value: isLit)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                    isLit.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            isLit
                            ? LinearGradient(
                                colors: [redCore, redDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [offFill, Color(red: 21 / 255, green: 21 / 255, blue: 27 / 255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 260, height: 260)
                        .overlay(
                            Circle()
                                .stroke(isLit ? redRim : offStroke, lineWidth: isLit ? 3.5 : 2.5)
                        )
                        .shadow(color: isLit ? redCore.opacity(0.85) : .black.opacity(0.6),
                                radius: isLit ? 32 : 16,
                                x: 0,
                                y: isLit ? 0 : 8)

                    Text("F")
                        .font(.system(size: 132, weight: .heavy, design: .rounded))
                        .foregroundColor(isLit ? .white : offText)
                        .shadow(color: isLit ? .white.opacity(0.45) : .clear, radius: 10)
                }
                .scaleEffect(isPressed ? 0.94 : 1.0)
            }
            .buttonStyle(PressScaleButtonStyle(isPressed: $isPressed))
            .accessibilityLabel("F Button")
            .accessibilityValue(isLit ? "On" : "Off")
        }
    }
}

private struct PressScaleButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { newValue in
                withAnimation(.easeOut(duration: 0.12)) {
                    isPressed = newValue
                }
            }
    }
}
