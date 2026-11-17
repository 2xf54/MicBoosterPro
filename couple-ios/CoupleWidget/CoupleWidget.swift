import WidgetKit
import SwiftUI

struct CoupleEntry: TimelineEntry {
    let date: Date
    let config: CoupleConfig
    let totalDays: Int
    let months: Int
    let daysRemainder: Int
    let yearProgress: Double
    let yearFloor: Int
    let startDateFormatted: String
    let distanceText: String
    let avatar1: UIImage?
    let avatar2: UIImage?
    let background: UIImage?
}

struct CoupleProvider: TimelineProvider {
    func placeholder(in context: Context) -> CoupleEntry {
        makeEntry(for: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CoupleEntry) -> Void) {
        completion(makeEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CoupleEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(for: now)

        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        let thirtyMin = now.addingTimeInterval(1800)
        let nextRefresh = min(tomorrow, thirtyMin)

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry(for date: Date) -> CoupleEntry {
        let store = CoupleStore.shared
        store.reload()
        let md = store.monthsAndDays(at: date)
        return CoupleEntry(
            date: date,
            config: store.config,
            totalDays: store.totalDays(at: date),
            months: md.months,
            daysRemainder: md.days,
            yearProgress: store.yearProgress(at: date),
            yearFloor: store.currentYearFloor(at: date),
            startDateFormatted: store.formattedStartDate(),
            distanceText: store.formattedDistance(),
            avatar1: store.avatar1Image,
            avatar2: store.avatar2Image,
            background: store.backgroundImage
        )
    }
}

struct WidgetAvatarView: View {
    let image: UIImage?
    let name: String
    let size: CGFloat
    var borderColor: Color = .white.opacity(0.85)
    var textColor: Color = .white

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                        .foregroundColor(textColor)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(borderColor, lineWidth: 1.5))

            Text(name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .lineLimit(1)
        }
    }
}

struct ArcShape: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY - 4)
        let radius = min(rect.width * 0.44, rect.height - 8)
        let startAngle = Angle.degrees(170)
        let totalSweep = 200.0
        let endAngle = Angle.degrees(170 + totalSweep * progress)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

struct CoupleHomeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CoupleEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumArcView
        default:
            largeView
        }
    }

    private var smallView: some View {
        ZStack {
            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: entry.config.accentHex))

                Text("\(entry.totalDays)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)

                Text(entry.totalDays == 1 ? "day" : "days")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .offset(y: -4)

                HStack(spacing: 5) {
                    Text(entry.config.partner1Name)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: entry.config.accentHex))
                    Text(entry.config.partner2Name)
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            }
            .padding(10)
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    private var mediumArcView: some View {
        ZStack {
            // Arc track & progress
            GeometryReader { geo in
                ZStack {
                    ArcShape(progress: 1.0)
                        .stroke(Color(hex: "4E2E2B").opacity(0.22), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    ArcShape(progress: entry.yearProgress)
                        .stroke(Color(hex: entry.config.accentHex), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                }
                .frame(width: geo.size.width, height: geo.size.height * 0.72)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
            }

            VStack(spacing: 2) {
                Spacer(minLength: 4)
                Text(entry.config.widgetTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "4E2E2B"))
                    .lineLimit(1)

                Text("\(entry.months) Month \(entry.daysRemainder) Day")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hex: "4E2E2B"))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(entry.config.showDistance ? "\(entry.config.widgetSubtitle) • \(entry.distanceText)" : entry.config.widgetSubtitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "4E2E2B").opacity(0.8))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Text("\(entry.yearFloor)y")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "4E2E2B").opacity(0.65))

                    Spacer()

                    WidgetAvatarView(
                        image: entry.avatar1,
                        name: entry.config.partner1Name,
                        size: 42,
                        borderColor: .white,
                        textColor: Color(hex: "4E2E2B")
                    )

                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: entry.config.accentHex))
                        .offset(y: -6)

                    WidgetAvatarView(
                        image: entry.avatar2,
                        name: entry.config.partner2Name,
                        size: 42,
                        borderColor: .white,
                        textColor: Color(hex: "4E2E2B")
                    )

                    Spacer()

                    Text("\(entry.yearFloor + 1)y")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "4E2E2B").opacity(0.65))
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
            }
            .padding(.vertical, 8)
        }
        .containerBackground(for: .widget) {
            Color(hex: entry.config.themeBgHex)
        }
    }

    private var largeView: some View {
        ZStack {
            VStack(spacing: 10) {
                Spacer()

                Text(entry.config.homeTitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                Text("\(entry.totalDays) days")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)

                Text(entry.startDateFormatted)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))

                if entry.config.showDistance {
                    Label(entry.distanceText, systemImage: "location.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.32)))
                }

                Spacer()

                HStack(spacing: 24) {
                    WidgetAvatarView(image: entry.avatar1, name: entry.config.partner1Name, size: 54)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .offset(y: -8)
                    WidgetAvatarView(image: entry.avatar2, name: entry.config.partner2Name, size: 54)
                }
                .padding(.bottom, 14)
            }
            .padding()
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if let bg = entry.background {
            ZStack {
                Image(uiImage: bg)
                    .resizable()
                    .scaledToFill()
                Color.black.opacity(0.32)
            }
        } else {
            LinearGradient(
                colors: [Color(hex: entry.config.themeBgHex).opacity(0.9), Color(hex: "2B2129")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct CoupleLockWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CoupleEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                Text("\(entry.totalDays)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text("days")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
            }
            .containerBackground(for: .widget) {
                Color.clear
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.config.homeTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.85)

                Text("\(entry.totalDays) days")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.7)

                HStack(spacing: 4) {
                    Text("\(entry.config.partner1Name) ♥ \(entry.config.partner2Name)")
                    if entry.config.showDistance {
                        Text("• \(entry.distanceText)")
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) {
                Color.clear
            }

        default:
            Text("♥ \(entry.totalDays) days • \(entry.config.partner1Name) & \(entry.config.partner2Name)")
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
    }
}

struct CoupleHomeWidget: Widget {
    let kind: String = "CoupleHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CoupleProvider()) { entry in
            CoupleHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("The Couple")
        .description("Days together, avatars, arc progress, and distance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CoupleLockWidget: Widget {
    let kind: String = "CoupleLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CoupleProvider()) { entry in
            CoupleLockWidgetView(entry: entry)
        }
        .configurationDisplayName("Couple Lock Screen")
        .description("Together counter on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct CoupleWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoupleHomeWidget()
        CoupleLockWidget()
    }
}
