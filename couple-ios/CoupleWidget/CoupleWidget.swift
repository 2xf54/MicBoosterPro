import WidgetKit
import SwiftUI

struct CoupleEntry: TimelineEntry {
    let date: Date
    let config: CoupleConfig
    let totalDays: Int
    let hours: Int
    let minutes: Int
    let months: Int
    let daysRemainder: Int
    let daysUntilNextYear: Int
    let yearProgress: Double
    let yearFloor: Int
    let startDateFormatted: String
    let distanceText: String
    let avatar1: UIImage?
    let avatar2: UIImage?
    let background: UIImage?
    let widgetBackground: UIImage?
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
        var entries: [CoupleEntry] = []
        let cal = Calendar.current

        for i in 0..<8 {
            let entryDate = now.addingTimeInterval(Double(i) * 900)
            entries.append(makeEntry(for: entryDate))
        }

        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        let nextRefresh = min(tomorrow, now.addingTimeInterval(7200))
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private func makeEntry(for date: Date) -> CoupleEntry {
        let store = CoupleStore.shared
        store.reload()
        let md = store.monthsAndDays(at: date)
        let parts = store.elapsedTimeParts(at: date)
        return CoupleEntry(
            date: date,
            config: store.config,
            totalDays: parts.days,
            hours: parts.hours,
            minutes: parts.minutes,
            months: md.months,
            daysRemainder: md.days,
            daysUntilNextYear: store.daysUntilNextYear(at: date),
            yearProgress: store.yearProgress(at: date),
            yearFloor: store.currentYearFloor(at: date),
            startDateFormatted: store.formattedStartDate(),
            distanceText: store.formattedDistance(),
            avatar1: store.avatar1Image,
            avatar2: store.avatar2Image,
            background: store.backgroundImage,
            widgetBackground: store.widgetBackgroundImage
        )
    }
}

struct WidgetAvatarView: View {
    let image: UIImage?
    let name: String
    let size: CGFloat
    var borderColor: Color = .white
    var textColor: Color = .white

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.28))
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                        .foregroundColor(textColor)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(borderColor, lineWidth: 1.5))

            Text(name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
                .lineLimit(1)
        }
    }
}

struct HorseshoeArcShape: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width * 0.36, rect.height * 0.45)
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let startDeg = 160.0
        let sweepDeg = 220.0
        let clamped = max(0.03, min(1.0, progress))
        let endDeg = startDeg + sweepDeg * clamped
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDeg),
            endAngle: .degrees(endDeg),
            clockwise: false
        )
        return path
    }
}

private func isDarkHex(_ hex: String) -> Bool {
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var val: UInt64 = 0
    Scanner(string: clean).scanHexInt64(&val)
    let r = Double((val >> 16) & 0xFF) / 255.0
    let g = Double((val >> 8) & 0xFF) / 255.0
    let b = Double(val & 0xFF) / 255.0
    let lum = 0.299 * r + 0.587 * g + 0.114 * b
    return lum < 0.5
}

// MARK: - 1. Couple Arc & Classic Widget
struct CoupleHomeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CoupleEntry

    private var activePhoto: UIImage? {
        if entry.config.widgetUsePhotoBg {
            return entry.widgetBackground ?? entry.background
        }
        return nil
    }

    private var inkColor: Color {
        if activePhoto != nil {
            return entry.config.useDarkTextOnPhoto ? Color(hex: "2B1D1B") : .white
        }
        return isDarkHex(entry.config.themeBgHex) ? .white : Color(hex: "4A2A27")
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            arcView(isLarge: false)
        default:
            arcView(isLarge: true)
        }
    }

    private var smallView: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 18))
                .foregroundColor(Color(hex: entry.config.accentHex))

            Text("\(entry.totalDays)")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(inkColor)
                .minimumScaleFactor(0.6)

            Text(entry.totalDays == 1 ? "day" : "days")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(inkColor.opacity(0.85))
                .offset(y: -4)

            HStack(spacing: 5) {
                Text(entry.config.partner1Name)
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: entry.config.accentHex))
                Text(entry.config.partner2Name)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(inkColor.opacity(0.92))
        }
        .padding(10)
        .containerBackground(for: .widget) {
            arcOrPhotoBackground
        }
    }

    private func arcView(isLarge: Bool) -> some View {
        let avatarSize: CGFloat = isLarge ? 56 : 34
        let titleSize: CGFloat = isLarge ? 16 : 11
        let mainSize: CGFloat = isLarge ? 25 : 16
        let subSize: CGFloat = isLarge ? 13 : 10
        let strokeW: CGFloat = isLarge ? 11 : 6.5

        return GeometryReader { geo in
            let radius = min(geo.size.width * 0.36, geo.size.height * 0.45)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + geo.size.height * 0.04)

            ZStack {
                // Arc track & active progress
                HorseshoeArcShape(progress: 1.0)
                    .stroke(inkColor.opacity(0.18), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                HorseshoeArcShape(progress: entry.yearProgress)
                    .stroke(Color(hex: entry.config.accentHex), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

                // 0y and 1y placed clearly outside the arc tips so they NEVER touch avatars
                Text("\(entry.yearFloor)y")
                    .font(.system(size: isLarge ? 13 : 10, weight: .bold, design: .rounded))
                    .foregroundColor(inkColor.opacity(0.72))
                    .position(
                        x: max(20, center.x - radius - (isLarge ? 22 : 16)),
                        y: center.y + radius * 0.48
                    )

                Text("\(entry.yearFloor + 1)y")
                    .font(.system(size: isLarge ? 13 : 10, weight: .bold, design: .rounded))
                    .foregroundColor(inkColor.opacity(0.72))
                    .position(
                        x: min(geo.size.width - 20, center.x + radius + (isLarge ? 22 : 16)),
                        y: center.y + radius * 0.48
                    )

                // Center content cleanly inside the arch
                VStack(spacing: isLarge ? 6 : 2) {
                    Text(entry.config.widgetTitle)
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .foregroundColor(inkColor)
                        .lineLimit(1)

                    Text("\(entry.months)Month \(entry.daysRemainder)Day")
                        .font(.system(size: mainSize, weight: .heavy, design: .rounded))
                        .foregroundColor(inkColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    let subText: String = {
                        let base = entry.config.widgetSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if entry.config.showDistance {
                            return base.isEmpty ? entry.distanceText : "\(base) • \(entry.distanceText)"
                        }
                        return base
                    }()

                    if !subText.isEmpty {
                        Text(subText)
                            .font(.system(size: subSize, weight: .bold, design: .rounded))
                            .foregroundColor(inkColor.opacity(0.84))
                            .lineLimit(1)
                    }

                    HStack(spacing: isLarge ? 16 : 8) {
                        WidgetAvatarView(
                            image: entry.avatar1,
                            name: entry.config.partner1Name,
                            size: avatarSize,
                            borderColor: .white,
                            textColor: inkColor
                        )

                        Image(systemName: "heart.fill")
                            .font(.system(size: isLarge ? 18 : 11))
                            .foregroundColor(Color(hex: entry.config.accentHex))
                            .offset(y: -5)

                        WidgetAvatarView(
                            image: entry.avatar2,
                            name: entry.config.partner2Name,
                            size: avatarSize,
                            borderColor: .white,
                            textColor: inkColor
                        )
                    }
                    .padding(.top, isLarge ? 10 : 3)
                }
                .frame(width: radius * 1.48)
                .position(x: center.x, y: center.y + (isLarge ? 10 : 4))
            }
        }
        .containerBackground(for: .widget) {
            arcOrPhotoBackground
        }
    }

    @ViewBuilder
    private var arcOrPhotoBackground: some View {
        if let photo = activePhoto {
            GeometryReader { geo in
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay(
                        (entry.config.useDarkTextOnPhoto ? Color.white : Color.black)
                            .opacity(entry.config.bgDimOpacity)
                    )
            }
        } else {
            Color(hex: entry.config.themeBgHex)
        }
    }
}

// MARK: - 2. Together Counter Widget (DAYS : HOUR : MIN)
struct CoupleCounterWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CoupleEntry

    private var activePhoto: UIImage? {
        if entry.config.widgetUsePhotoBg {
            return entry.widgetBackground ?? entry.background
        }
        return entry.background
    }

    private var fgColor: Color {
        if activePhoto != nil {
            return entry.config.useDarkTextOnPhoto ? Color(hex: "231817") : .white
        }
        return isDarkHex(entry.config.themeBgHex) ? .white : Color(hex: "2B1D1B")
    }

    var body: some View {
        VStack(spacing: family == .systemSmall ? 4 : 8) {
            Text(entry.config.homeTitle)
                .font(.system(size: family == .systemSmall ? 11 : 13, weight: .semibold, design: .rounded))
                .foregroundColor(fgColor.opacity(0.88))

            if family == .systemSmall {
                Text("\(entry.totalDays)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(fgColor)
                Text("DAYS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(fgColor.opacity(0.75))
                Text("\(entry.daysUntilNextYear)d to \(entry.yearFloor + 1)y")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(fgColor.opacity(0.85))
            } else {
                HStack(spacing: 12) {
                    CounterCol(val: "\(entry.totalDays)", label: "DAYS", color: fgColor)
                    Text(":").font(.system(size: 22, weight: .bold)).foregroundColor(fgColor.opacity(0.5)).offset(y: -6)
                    CounterCol(val: String(format: "%02d", entry.hours), label: "HOUR", color: fgColor)
                    Text(":").font(.system(size: 22, weight: .bold)).foregroundColor(fgColor.opacity(0.5)).offset(y: -6)
                    CounterCol(val: String(format: "%02d", entry.minutes), label: "MIN", color: fgColor)
                }

                HStack(spacing: 6) {
                    Text("\(entry.config.partner1Name) ♥ \(entry.config.partner2Name)")
                    Text("• \(entry.daysUntilNextYear)d to \(entry.yearFloor + 1)y")
                    if entry.config.showDistance {
                        Text("• \(entry.distanceText)")
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(fgColor.opacity(0.88))
                .lineLimit(1)
            }
        }
        .padding(10)
        .containerBackground(for: .widget) {
            if let bg = activePhoto {
                GeometryReader { geo in
                    Image(uiImage: bg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(
                            (entry.config.useDarkTextOnPhoto ? Color.white : Color.black)
                                .opacity(entry.config.bgDimOpacity)
                        )
                }
            } else {
                Color(hex: entry.config.themeBgHex)
            }
        }
    }
}

private struct CounterCol: View {
    let val: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(val)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(color.opacity(0.75))
        }
    }
}

// MARK: - 3. Lock Screen Widget
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
            .containerBackground(for: .widget) { Color.clear }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.config.homeTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.85)

                Text(String(format: "%d:%02d:%02d", entry.totalDays, entry.hours, entry.minutes))
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    Text("DAYS : HRS : MIN")
                    if entry.config.showDistance {
                        Text("• \(entry.distanceText)")
                    }
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }

        default:
            Text("♥ \(entry.totalDays) days • \(entry.config.partner1Name) & \(entry.config.partner2Name)")
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

struct CoupleHomeWidget: Widget {
    let kind: String = "CoupleHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CoupleProvider()) { entry in
            CoupleHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Been Together (Arc)")
        .description("Horseshoe arc with avatars, months/days, and 0y-1y progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CoupleCounterWidget: Widget {
    let kind: String = "CoupleCounterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CoupleProvider()) { entry in
            CoupleCounterWidgetView(entry: entry)
        }
        .configurationDisplayName("Together Counter")
        .description("DAYS : HOUR : MIN counter with background & distance.")
        .supportedFamilies([.systemSmall, .systemMedium])
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
        CoupleCounterWidget()
        CoupleLockWidget()
    }
}
