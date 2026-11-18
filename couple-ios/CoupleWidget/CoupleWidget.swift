import WidgetKit
import SwiftUI
import AppIntents

enum WidgetThemeColor: String, AppEnum {
    case rosePink = "DEB6BE"
    case pureWhite = "FFFFFF"
    case softCream = "F7EFE5"
    case softPeach = "E8C3B9"
    case lavender = "C8BFE7"
    case skyBlue = "B8D8EB"
    case midnight = "161824"
    case crimson = "2A1219"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Theme Color"
    static var caseDisplayRepresentations: [WidgetThemeColor: DisplayRepresentation] = [
        .rosePink: "Rose Pink",
        .pureWhite: "Pure White",
        .softCream: "Soft Cream",
        .softPeach: "Soft Peach",
        .lavender: "Lavender",
        .skyBlue: "Sky Blue",
        .midnight: "Midnight",
        .crimson: "Crimson Night"
    ]
}

enum WidgetCityChoice: String, AppEnum {
    case riyadh = "Riyadh"
    case alkharj = "Al-Kharj"
    case jeddah = "Jeddah"
    case makkah = "Makkah"
    case madinah = "Madinah"
    case dammam = "Dammam"
    case khobar = "Khobar"
    case jazan = "Jazan"
    case abha = "Abha"
    case najran = "Najran"
    case taif = "Taif"
    case tabuk = "Tabuk"
    case hail = "Hail"
    case buraydah = "Buraydah"
    case yanbu = "Yanbu"
    case jubail = "Jubail"
    case alahsa = "Al-Ahsa"
    case dubai = "Dubai"
    case doha = "Doha"
    case kuwait = "Kuwait City"
    case cairo = "Cairo"
    case london = "London"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "City"
    static var caseDisplayRepresentations: [WidgetCityChoice: DisplayRepresentation] = [
        .riyadh: "Riyadh (الرياض)",
        .alkharj: "Al-Kharj (الخرج)",
        .jeddah: "Jeddah (جدة)",
        .makkah: "Makkah (مكة)",
        .madinah: "Madinah (المدينة)",
        .dammam: "Dammam (الدمام)",
        .khobar: "Khobar (الخبر)",
        .jazan: "Jazan (جازان)",
        .abha: "Abha (أبها)",
        .najran: "Najran (نجران)",
        .taif: "Taif (الطائف)",
        .tabuk: "Tabuk (تبوك)",
        .hail: "Hail (حائل)",
        .buraydah: "Buraydah (بريدة)",
        .yanbu: "Yanbu (ينبع)",
        .jubail: "Jubail (الجبيل)",
        .alahsa: "Al-Ahsa (الأحساء)",
        .dubai: "Dubai (دبي)",
        .doha: "Doha (الدوحة)",
        .kuwait: "Kuwait (الكويت)",
        .cairo: "Cairo (القاهرة)",
        .london: "London (لندن)"
    ]
}

struct CoupleWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Couple Widget Settings"
    static var description = IntentDescription("Customize date, names, subtitle, color, and cities directly on the widget.")

    @Parameter(title: "Start Date")
    var startDate: Date?

    @Parameter(title: "Your Name", default: "G")
    var partner1Name: String

    @Parameter(title: "Partner Name", default: "R")
    var partner2Name: String

    @Parameter(title: "Title", default: "Been together 🐰")
    var widgetTitle: String

    @Parameter(title: "Subtitle", default: "GRG")
    var widgetSubtitle: String

    @Parameter(title: "Background Color", default: .rosePink)
    var themeColor: WidgetThemeColor

    @Parameter(title: "Show Distance", default: true)
    var showDistance: Bool

    @Parameter(title: "Your City", default: .riyadh)
    var city1: WidgetCityChoice

    @Parameter(title: "Partner City", default: .jeddah)
    var city2: WidgetCityChoice
}

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

struct CoupleIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CoupleEntry {
        makeEntry(for: Date(), intent: CoupleWidgetIntent())
    }

    func snapshot(for configuration: CoupleWidgetIntent, in context: Context) async -> CoupleEntry {
        makeEntry(for: Date(), intent: configuration)
    }

    func timeline(for configuration: CoupleWidgetIntent, in context: Context) async -> Timeline<CoupleEntry> {
        let now = Date()
        var entries: [CoupleEntry] = []
        let cal = Calendar.current

        for i in 0..<8 {
            let entryDate = now.addingTimeInterval(Double(i) * 900)
            entries.append(makeEntry(for: entryDate, intent: configuration))
        }

        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        let nextRefresh = min(tomorrow, now.addingTimeInterval(7200))
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }

    private func makeEntry(for date: Date, intent: CoupleWidgetIntent) -> CoupleEntry {
        let store = CoupleStore.shared
        store.reload()

        // If App Group is not linked, or user explicitly set a Start Date in Edit Widget, apply intent values
        var effectiveConfig = store.config
        if !store.isAppGroupAvailable || intent.startDate != nil {
            if let sd = intent.startDate {
                effectiveConfig.startDate = sd
            }
            effectiveConfig.partner1Name = intent.partner1Name
            effectiveConfig.partner2Name = intent.partner2Name
            effectiveConfig.widgetTitle = intent.widgetTitle
            effectiveConfig.widgetSubtitle = intent.widgetSubtitle
            effectiveConfig.themeBgHex = intent.themeColor.rawValue
            effectiveConfig.showDistance = intent.showDistance
            if let c1 = CityPreset.presets.first(where: { $0.name == intent.city1.rawValue }) {
                effectiveConfig.city1Name = c1.name
                effectiveConfig.city1Lat = c1.lat
                effectiveConfig.city1Lon = c1.lon
            }
            if let c2 = CityPreset.presets.first(where: { $0.name == intent.city2.rawValue }) {
                effectiveConfig.city2Name = c2.name
                effectiveConfig.city2Lat = c2.lat
                effectiveConfig.city2Lon = c2.lon
            }
        }

        // Compute values using effectiveConfig
        let tempStore = CoupleStore()
        tempStore.config = effectiveConfig
        let md = tempStore.monthsAndDays(at: date)
        let parts = tempStore.elapsedTimeParts(at: date)

        return CoupleEntry(
            date: date,
            config: effectiveConfig,
            totalDays: parts.days,
            hours: parts.hours,
            minutes: parts.minutes,
            months: md.months,
            daysRemainder: md.days,
            daysUntilNextYear: tempStore.daysUntilNextYear(at: date),
            yearProgress: tempStore.yearProgress(at: date),
            yearFloor: tempStore.currentYearFloor(at: date),
            startDateFormatted: tempStore.formattedStartDate(),
            distanceText: tempStore.formattedDistance(),
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
                HorseshoeArcShape(progress: 1.0)
                    .stroke(inkColor.opacity(0.18), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                HorseshoeArcShape(progress: entry.yearProgress)
                    .stroke(Color(hex: entry.config.accentHex), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

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
        AppIntentConfiguration(kind: kind, intent: CoupleWidgetIntent.self, provider: CoupleIntentProvider()) { entry in
            CoupleHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Been Together (Arc)")
        .description("Hold widget -> Edit Widget to set date, names, subtitle, color & cities.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CoupleCounterWidget: Widget {
    let kind: String = "CoupleCounterWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CoupleWidgetIntent.self, provider: CoupleIntentProvider()) { entry in
            CoupleCounterWidgetView(entry: entry)
        }
        .configurationDisplayName("Together Counter")
        .description("DAYS : HOUR : MIN counter. Hold widget -> Edit Widget to customize.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CoupleLockWidget: Widget {
    let kind: String = "CoupleLockWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CoupleWidgetIntent.self, provider: CoupleIntentProvider()) { entry in
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
