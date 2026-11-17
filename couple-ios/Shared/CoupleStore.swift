import Foundation
import SwiftUI
import UIKit
import WidgetKit
import CoreLocation

struct CoupleMemo: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var date: Date = Date()
}

struct CoupleStory: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var note: String
    var date: Date
}

struct CityPreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let arabicName: String
    let lat: Double
    let lon: Double

    var displayLabel: String { "\(name) (\(arabicName))" }

    static let presets: [CityPreset] = [
        // Saudi Arabia
        CityPreset(name: "Riyadh", arabicName: "الرياض", lat: 24.7136, lon: 46.6753),
        CityPreset(name: "Al-Kharj", arabicName: "الخرج", lat: 24.1556, lon: 47.3120),
        CityPreset(name: "Jeddah", arabicName: "جدة", lat: 21.4858, lon: 39.1925),
        CityPreset(name: "Makkah", arabicName: "مكة", lat: 21.3891, lon: 39.8579),
        CityPreset(name: "Madinah", arabicName: "المدينة", lat: 24.5247, lon: 39.5692),
        CityPreset(name: "Dammam", arabicName: "الدمام", lat: 26.4207, lon: 50.0888),
        CityPreset(name: "Khobar", arabicName: "الخبر", lat: 26.2172, lon: 50.1971),
        CityPreset(name: "Dhahran", arabicName: "الظهران", lat: 26.2361, lon: 50.0393),
        CityPreset(name: "Jubail", arabicName: "الجبيل", lat: 27.0112, lon: 49.6583),
        CityPreset(name: "Al-Ahsa", arabicName: "الأحساء", lat: 25.3833, lon: 49.5833),
        CityPreset(name: "Qatif", arabicName: "القطيف", lat: 26.5196, lon: 50.0115),
        CityPreset(name: "Jazan", arabicName: "جازان", lat: 16.8892, lon: 42.5511),
        CityPreset(name: "Abha", arabicName: "أبها", lat: 18.2164, lon: 42.5053),
        CityPreset(name: "Khamis Mushait", arabicName: "خميس مشيط", lat: 18.3000, lon: 42.7333),
        CityPreset(name: "Najran", arabicName: "نجران", lat: 17.4933, lon: 44.1277),
        CityPreset(name: "Al-Baha", arabicName: "الباحة", lat: 20.0129, lon: 41.4677),
        CityPreset(name: "Taif", arabicName: "الطائف", lat: 21.2703, lon: 40.4158),
        CityPreset(name: "Yanbu", arabicName: "ينبع", lat: 24.0895, lon: 38.0618),
        CityPreset(name: "Tabuk", arabicName: "تبوك", lat: 28.3835, lon: 36.5662),
        CityPreset(name: "Al-Ula", arabicName: "العلا", lat: 26.6177, lon: 37.9232),
        CityPreset(name: "Hail", arabicName: "حائل", lat: 27.5114, lon: 41.7208),
        CityPreset(name: "Buraydah", arabicName: "بريدة", lat: 26.3260, lon: 43.9750),
        CityPreset(name: "Unaizah", arabicName: "عنيزة", lat: 26.0840, lon: 43.9935),
        CityPreset(name: "Hafr Al-Batin", arabicName: "حفر الباطن", lat: 28.4328, lon: 45.9708),
        CityPreset(name: "Sakaka", arabicName: "سكاكا", lat: 29.9697, lon: 40.2064),
        CityPreset(name: "Arar", arabicName: "عرعر", lat: 30.9753, lon: 41.0381),
        CityPreset(name: "Al-Majmaah", arabicName: "المجمعة", lat: 25.9039, lon: 45.3444),
        CityPreset(name: "Al-Zulfi", arabicName: "الزلفي", lat: 26.2994, lon: 44.8156),
        CityPreset(name: "Al-Dawadmi", arabicName: "الدوادمي", lat: 24.5071, lon: 44.3924),
        CityPreset(name: "Wadi Al-Dawasir", arabicName: "وادي الدواسر", lat: 20.4606, lon: 44.7924),
        CityPreset(name: "Bisha", arabicName: "بيشة", lat: 20.0005, lon: 42.6052),
        // GCC & Arab World
        CityPreset(name: "Dubai", arabicName: "دبي", lat: 25.2048, lon: 55.2708),
        CityPreset(name: "Abu Dhabi", arabicName: "أبوظبي", lat: 24.4539, lon: 54.3773),
        CityPreset(name: "Sharjah", arabicName: "الشارقة", lat: 25.3463, lon: 55.4209),
        CityPreset(name: "Doha", arabicName: "الدوحة", lat: 25.2854, lon: 51.5310),
        CityPreset(name: "Kuwait City", arabicName: "الكويت", lat: 29.3759, lon: 47.9774),
        CityPreset(name: "Manama", arabicName: "المنامة", lat: 26.2285, lon: 50.5860),
        CityPreset(name: "Muscat", arabicName: "مسقط", lat: 23.5880, lon: 58.3829),
        CityPreset(name: "Cairo", arabicName: "القاهرة", lat: 30.0444, lon: 31.2357),
        CityPreset(name: "Alexandria", arabicName: "الإسكندرية", lat: 31.2001, lon: 29.9187),
        CityPreset(name: "Amman", arabicName: "عمّان", lat: 31.9454, lon: 35.9284),
        CityPreset(name: "Beirut", arabicName: "بيروت", lat: 33.8938, lon: 35.5018),
        CityPreset(name: "Baghdad", arabicName: "بغداد", lat: 33.3152, lon: 44.3661),
        CityPreset(name: "Casablanca", arabicName: "الدار البيضاء", lat: 33.5731, lon: -7.5898),
        // World
        CityPreset(name: "Istanbul", arabicName: "إسطنبول", lat: 41.0082, lon: 28.9784),
        CityPreset(name: "London", arabicName: "لندن", lat: 51.5072, lon: -0.1276),
        CityPreset(name: "Paris", arabicName: "باريس", lat: 48.8566, lon: 2.3522),
        CityPreset(name: "New York", arabicName: "نيويورك", lat: 40.7128, lon: -74.0060),
        CityPreset(name: "Los Angeles", arabicName: "لوس أنجلوس", lat: 34.0522, lon: -118.2437),
        CityPreset(name: "Toronto", arabicName: "تورونتو", lat: 43.6532, lon: -79.3832),
        CityPreset(name: "Tokyo", arabicName: "طوكيو", lat: 35.6762, lon: 139.6503),
        CityPreset(name: "Seoul", arabicName: "سيول", lat: 37.5665, lon: 126.9780)
    ]
}

struct CoupleConfig: Codable {
    var startDate: Date = Calendar.current.date(byAdding: .day, value: -120, to: Date()) ?? Date()
    var partner1Name: String = "G"
    var partner2Name: String = "R"
    var homeTitle: String = "Together for"
    var widgetTitle: String = "Been together 🐰"
    var widgetSubtitle: String = "GRG"
    var themeBgHex: String = "DEB6BE"
    var accentHex: String = "FF7D85"
    var countInclusive: Bool = false
    var useDarkTextOnPhoto: Bool = false
    var bgDimOpacity: Double = 0.35

    var showDistance: Bool = true
    var city1Name: String = "Riyadh"
    var city1Lat: Double = 24.7136
    var city1Lon: Double = 46.6753
    var city2Name: String = "Jeddah"
    var city2Lat: Double = 21.4858
    var city2Lon: Double = 39.1925
}

final class CoupleStore: ObservableObject {
    static let shared = CoupleStore()
    static let appGroupID = "group.com.ghazi.coupleapp"

    @Published var config: CoupleConfig = CoupleConfig()
    @Published var memos: [CoupleMemo] = []
    @Published var stories: [CoupleStory] = []
    @Published var avatar1Image: UIImage?
    @Published var avatar2Image: UIImage?
    @Published var backgroundImage: UIImage?

    var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) != nil
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    private var sharedContainerURL: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            return groupURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        reload()
    }

    func reload() {
        if let data = defaults.data(forKey: "couple_config_v1"),
           let decoded = try? JSONDecoder().decode(CoupleConfig.self, from: data) {
            config = decoded
        }
        if let data = defaults.data(forKey: "couple_memos_v1"),
           let decoded = try? JSONDecoder().decode([CoupleMemo].self, from: data) {
            memos = decoded
        }
        if let data = defaults.data(forKey: "couple_stories_v1"),
           let decoded = try? JSONDecoder().decode([CoupleStory].self, from: data) {
            stories = decoded
        }
        avatar1Image = loadImage(named: "avatar1.jpg", defaultsKey: "avatar1_data")
        avatar2Image = loadImage(named: "avatar2.jpg", defaultsKey: "avatar2_data")
        backgroundImage = loadImage(named: "background.jpg", defaultsKey: "background_data")
    }

    func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            defaults.set(encoded, forKey: "couple_config_v1")
            defaults.synchronize()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func saveMemos() {
        if let encoded = try? JSONEncoder().encode(memos) {
            defaults.set(encoded, forKey: "couple_memos_v1")
            defaults.synchronize()
        }
    }

    func saveStories() {
        if let encoded = try? JSONEncoder().encode(stories) {
            defaults.set(encoded, forKey: "couple_stories_v1")
            defaults.synchronize()
        }
    }

    func saveImage(_ image: UIImage?, named filename: String, maxDimension: CGFloat = 450) {
        let defaultsKey = filename.replacingOccurrences(of: ".jpg", with: "_data")
        let url = sharedContainerURL.appendingPathComponent(filename)
        if let img = image {
            let resized = Self.resizeImage(img, maxDimension: maxDimension)
            if let data = resized.jpegData(compressionQuality: 0.78) {
                try? data.write(to: url, options: .atomic)
                if data.count < 900_000 {
                    defaults.set(data, forKey: defaultsKey)
                    defaults.synchronize()
                }
            }
        } else {
            try? FileManager.default.removeItem(at: url)
            defaults.removeObject(forKey: defaultsKey)
            defaults.synchronize()
        }
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func loadImage(named filename: String, defaultsKey: String) -> UIImage? {
        let url = sharedContainerURL.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return img
        }
        if let data = defaults.data(forKey: defaultsKey), let img = UIImage(data: data) {
            return img
        }
        return nil
    }

    static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Date & Distance Calculations

    func totalDays(at date: Date = Date()) -> Int {
        let totalSec = max(0, Int(date.timeIntervalSince(config.startDate)))
        let d = totalSec / 86400
        return max(0, d + (config.countInclusive ? 1 : 0))
    }

    func elapsedTimeParts(at date: Date = Date()) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let totalSec = max(0, Int(date.timeIntervalSince(config.startDate)))
        let d = (totalSec / 86400) + (config.countInclusive ? 1 : 0)
        let h = (totalSec % 86400) / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return (d, h, m, s)
    }

    func monthsAndDays(at date: Date = Date()) -> (months: Int, days: Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: config.startDate)
        let end = cal.startOfDay(for: date)
        let comps = cal.dateComponents([.month, .day], from: start, to: end)
        return (max(0, comps.month ?? 0), max(0, comps.day ?? 0))
    }

    func yearsMonthsDays(at date: Date = Date()) -> (years: Int, months: Int, days: Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: config.startDate)
        let end = cal.startOfDay(for: date)
        let comps = cal.dateComponents([.year, .month, .day], from: start, to: end)
        return (max(0, comps.year ?? 0), max(0, comps.month ?? 0), max(0, comps.day ?? 0))
    }

    func daysUntilNextYear(at date: Date = Date()) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: config.startDate)
        let today = cal.startOfDay(for: date)
        let currentYear = yearsMonthsDays(at: date).years
        guard let nextAnniv = cal.date(byAdding: .year, value: currentYear + 1, to: start) else { return 0 }
        return max(0, cal.dateComponents([.day], from: today, to: nextAnniv).day ?? 0)
    }

    func yearProgress(at date: Date = Date()) -> Double {
        let days = totalDays(at: date)
        let mod = days % 365
        if days > 0 && mod == 0 { return 1.0 }
        return min(1.0, max(0.04, Double(mod) / 365.0))
    }

    func currentYearFloor(at date: Date = Date()) -> Int {
        yearsMonthsDays(at: date).years
    }

    func formattedStartDate() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: config.startDate)
    }

    func distanceKm() -> Double {
        let loc1 = CLLocation(latitude: config.city1Lat, longitude: config.city1Lon)
        let loc2 = CLLocation(latitude: config.city2Lat, longitude: config.city2Lon)
        return loc1.distance(from: loc2) / 1000.0
    }

    func formattedDistance() -> String {
        let km = distanceKm()
        if km < 1.0 {
            return "\(Int(km * 1000)) m"
        } else if km < 10.0 {
            return String(format: "%.1f km", km)
        } else {
            return "\(Int(km.rounded())) km"
        }
    }

    func upcomingMilestones(at date: Date = Date()) -> [(label: String, targetDate: Date, daysLeft: Int)] {
        let targets = [100, 200, 300, 365, 500, 730, 1000, 1095, 1500, 2000, 3650]
        let cal = Calendar.current
        let start = cal.startOfDay(for: config.startDate)
        let today = cal.startOfDay(for: date)
        var result: [(String, Date, Int)] = []
        for t in targets {
            let offset = config.countInclusive ? (t - 1) : t
            if let targetDate = cal.date(byAdding: .day, value: offset, to: start) {
                let left = cal.dateComponents([.day], from: today, to: targetDate).day ?? 0
                let label = (t % 365 == 0) ? "\(t / 365) Year\(t / 365 > 1 ? "s" : "") (\(t) Days)" : "\(t) Days"
                result.append((label, targetDate, left))
            }
        }
        return result
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 125, 133)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}
