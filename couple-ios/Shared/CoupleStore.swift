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
    let lat: Double
    let lon: Double

    static let presets: [CityPreset] = [
        CityPreset(name: "Riyadh", lat: 24.7136, lon: 46.6753),
        CityPreset(name: "Jeddah", lat: 21.4858, lon: 39.1925),
        CityPreset(name: "Dammam", lat: 26.4207, lon: 50.0888),
        CityPreset(name: "Khobar", lat: 26.2172, lon: 50.1971),
        CityPreset(name: "Makkah", lat: 21.3891, lon: 39.8579),
        CityPreset(name: "Madinah", lat: 24.5247, lon: 39.5692),
        CityPreset(name: "Abha", lat: 18.2164, lon: 42.5053),
        CityPreset(name: "Taif", lat: 21.2703, lon: 40.4158),
        CityPreset(name: "Tabuk", lat: 28.3835, lon: 36.5662),
        CityPreset(name: "Hail", lat: 27.5114, lon: 41.7208),
        CityPreset(name: "Qassim", lat: 26.3260, lon: 43.9750),
        CityPreset(name: "Dubai", lat: 25.2048, lon: 55.2708),
        CityPreset(name: "Abu Dhabi", lat: 24.4539, lon: 54.3773),
        CityPreset(name: "Doha", lat: 25.2854, lon: 51.5310),
        CityPreset(name: "Kuwait City", lat: 29.3759, lon: 47.9774),
        CityPreset(name: "Manama", lat: 26.2285, lon: 50.5860),
        CityPreset(name: "Muscat", lat: 23.5880, lon: 58.3829),
        CityPreset(name: "Cairo", lat: 30.0444, lon: 31.2357),
        CityPreset(name: "Amman", lat: 31.9454, lon: 35.9284),
        CityPreset(name: "London", lat: 51.5072, lon: -0.1276),
        CityPreset(name: "Tokyo", lat: 35.6762, lon: 139.6503)
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
    var countInclusive: Bool = true

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
        avatar1Image = loadImage(named: "avatar1.jpg")
        avatar2Image = loadImage(named: "avatar2.jpg")
        backgroundImage = loadImage(named: "background.jpg")
    }

    func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            defaults.set(encoded, forKey: "couple_config_v1")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func saveMemos() {
        if let encoded = try? JSONEncoder().encode(memos) {
            defaults.set(encoded, forKey: "couple_memos_v1")
        }
    }

    func saveStories() {
        if let encoded = try? JSONEncoder().encode(stories) {
            defaults.set(encoded, forKey: "couple_stories_v1")
        }
    }

    func saveImage(_ image: UIImage?, named filename: String, maxDimension: CGFloat = 650) {
        let url = sharedContainerURL.appendingPathComponent(filename)
        if let img = image {
            let resized = Self.resizeImage(img, maxDimension: maxDimension)
            if let data = resized.jpegData(compressionQuality: 0.85) {
                try? data.write(to: url, options: .atomic)
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func loadImage(named filename: String) -> UIImage? {
        let url = sharedContainerURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
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
        let cal = Calendar.current
        let start = cal.startOfDay(for: config.startDate)
        let end = cal.startOfDay(for: date)
        let diff = cal.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, diff + (config.countInclusive ? 1 : 0))
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

    func formattedElapsed(at date: Date = Date()) -> String {
        let days = totalDays(at: date)
        let ymd = yearsMonthsDays(at: date)
        if ymd.years >= 1 {
            return ymd.years == 1 ? "1 year" : "\(ymd.years) years"
        }
        return days == 1 ? "1 day" : "\(days) days"
    }

    func yearProgress(at date: Date = Date()) -> Double {
        let days = totalDays(at: date)
        let mod = days % 365
        if days > 0 && mod == 0 { return 1.0 }
        return min(1.0, max(0.05, Double(mod) / 365.0))
    }

    func currentYearFloor(at date: Date = Date()) -> Int {
        totalDays(at: date) / 365
    }

    func formattedStartDate() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
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
