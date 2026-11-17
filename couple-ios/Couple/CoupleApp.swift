import SwiftUI
import PhotosUI
import WidgetKit

enum CoupleTab: String, CaseIterable {
    case home = "Home"
    case story = "Story"
    case memo = "Memo"
    case my = "My"

    var icon: String {
        switch self {
        case .home: return "heart.fill"
        case .story: return "book.closed.fill"
        case .memo: return "note.text"
        case .my: return "person.fill"
        }
    }
}

@main
struct CoupleApp: App {
    @StateObject private var store = CoupleStore.shared

    var body: some Scene {
        WindowGroup {
            MainTabContainer()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct MainTabContainer: View {
    @EnvironmentObject var store: CoupleStore
    @State private var selectedTab: CoupleTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    HomeTabView()
                case .story:
                    StoryTabView()
                case .memo:
                    MemoTabView()
                case .my:
                    MySettingsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating glassy bottom bar matching The Couple UI
            HStack(spacing: 4) {
                ForEach(CoupleTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? Color.white.opacity(0.22) : Color.clear)
                        )
                    }
                }
            }
            .padding(6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Home Tab
struct HomeTabView: View {
    @EnvironmentObject var store: CoupleStore
    @State private var displayMode: Int = 0 // 0 = days, 1 = y/m/d, 2 = live timer
    @State private var showCustomize = false
    @State private var editingPartner: Int? = nil
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background
            // Background locked strictly to screen bounds so bottom bar never shifts or freezes
            GeometryReader { geo in
                if let bg = store.backgroundImage {
                    Image(uiImage: bg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(
                            (store.config.useDarkTextOnPhoto ? Color.white : Color.black)
                                .opacity(store.config.bgDimOpacity)
                        )
                } else {
                    LinearGradient(
                        colors: [Color(hex: store.config.themeBgHex).opacity(0.85), Color(hex: "2B2129"), Color(hex: "141118")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                // Top-right customize button
                HStack {
                    Spacer()
                    Button {
                        showCustomize = true
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                // Main counter
                VStack(spacing: 8) {
                    Text(store.config.homeTitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 4)

                    if displayMode == 2 {
                        let p = store.elapsedTimeParts(at: now)
                        HStack(spacing: 14) {
                            TimerUnitColumn(value: "\(p.days)", label: "DAYS")
                            Text(":").font(.system(size: 26, weight: .bold)).foregroundColor(.white.opacity(0.6)).offset(y: -8)
                            TimerUnitColumn(value: String(format: "%02d", p.hours), label: "HOUR")
                            Text(":").font(.system(size: 26, weight: .bold)).foregroundColor(.white.opacity(0.6)).offset(y: -8)
                            TimerUnitColumn(value: String(format: "%02d", p.minutes), label: "MIN")
                            Text(":").font(.system(size: 26, weight: .bold)).foregroundColor(.white.opacity(0.6)).offset(y: -8)
                            TimerUnitColumn(value: String(format: "%02d", p.seconds), label: "SEC")
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                displayMode = (displayMode + 1) % 3
                            }
                        }
                    } else {
                        Text(counterTitle)
                            .font(.system(size: 52, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.4), radius: 8)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    displayMode = (displayMode + 1) % 3
                                }
                            }
                    }

                    Text("\(store.formattedStartDate()) • \(store.daysUntilNextYear(at: now))d until \(store.currentYearFloor(at: now) + 1)y")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.35), radius: 4)

                    if store.config.showDistance {
                        Label("\(store.config.city1Name) ↔ \(store.config.city2Name) • \(store.formattedDistance())", systemImage: "location.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Two avatars & heart
                HStack(spacing: 34) {
                    Button { editingPartner = 1 } label: {
                        HomeAvatarBubble(image: store.avatar1Image, name: store.config.partner1Name)
                    }

                    Image(systemName: "heart.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .shadow(color: Color(hex: store.config.accentHex).opacity(0.8), radius: 8)
                        .offset(y: -12)

                    Button { editingPartner = 2 } label: {
                        HomeAvatarBubble(image: store.avatar2Image, name: store.config.partner2Name)
                    }
                }
                .padding(.bottom, 96)
            }
        }
        .onReceive(timer) { t in
            if displayMode == 2 { now = t }
        }
        .sheet(isPresented: $showCustomize) {
            CustomizeThemeSheet()
        }
        .sheet(item: Binding(
            get: { editingPartner.map { PartnerSheetItem(id: $0) } },
            set: { editingPartner = $0?.id }
        )) { item in
            EditPartnerSheet(partnerIndex: item.id)
        }
    }

    private var counterTitle: String {
        switch displayMode {
        case 1:
            let ymd = store.yearsMonthsDays(at: now)
            if ymd.years > 0 {
                return "\(ymd.years)y \(ymd.months)m \(ymd.days)d"
            }
            return "\(ymd.months)m \(ymd.days)d"
        case 2:
            let totalSec = max(0, Int(now.timeIntervalSince(store.config.startDate)))
            let d = totalSec / 86400
            let h = (totalSec % 86400) / 3600
            let m = (totalSec % 3600) / 60
            let s = totalSec % 60
            return String(format: "%d : %02d : %02d : %02d", d, h, m, s)
        default:
            let d = store.totalDays(at: now)
            return d == 1 ? "1 day" : "\(d) days"
        }
    }
}

private struct TimerUnitColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}

private struct PartnerSheetItem: Identifiable {
    let id: Int
}

struct HomeAvatarBubble: View {
    let image: UIImage?
    let name: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.18))
                    Image(systemName: "face.smiling")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 8)

            Text(name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.45), radius: 4)
        }
    }
}

// MARK: - Edit Partner Sheet
struct EditPartnerSheet: View {
    @EnvironmentObject var store: CoupleStore
    @Environment(\.dismiss) var dismiss
    let partnerIndex: Int
    @State private var nameText: String = ""
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Partner Name") {
                    TextField("Name", text: $nameText)
                }
                Section("Avatar Photo") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Choose Photo from Library", systemImage: "photo.on.rectangle")
                    }
                    Button(role: .destructive) {
                        store.saveImage(nil, named: partnerIndex == 1 ? "avatar1.jpg" : "avatar2.jpg")
                    } label: {
                        Text("Remove Avatar")
                    }
                }
            }
            .navigationTitle(partnerIndex == 1 ? "Partner 1" : "Partner 2")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if partnerIndex == 1 {
                            store.config.partner1Name = nameText.isEmpty ? "G" : nameText
                        } else {
                            store.config.partner2Name = nameText.isEmpty ? "R" : nameText
                        }
                        store.saveConfig()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                nameText = partnerIndex == 1 ? store.config.partner1Name : store.config.partner2Name
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            store.saveImage(img, named: partnerIndex == 1 ? "avatar1.jpg" : "avatar2.jpg", maxDimension: 400)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Customize Theme Sheet
struct CustomizeThemeSheet: View {
    @EnvironmentObject var store: CoupleStore
    @Environment(\.dismiss) var dismiss
    @State private var bgItem: PhotosPickerItem?

    private let bgPresets: [(String, String)] = [
        ("Rose Pink", "DEB6BE"),
        ("Soft Peach", "E8C3B9"),
        ("Lavender", "C8BFE7"),
        ("Midnight", "161824"),
        ("Crimson Night", "2A1219")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Background Photo") {
                    PhotosPicker(selection: $bgItem, matching: .images) {
                        Label("Choose Wallpaper from Photos", systemImage: "photo.fill")
                    }
                    if store.backgroundImage != nil {
                        Button(role: .destructive) {
                            store.saveImage(nil, named: "background.jpg")
                        } label: {
                            Text("Remove Wallpaper")
                        }
                    }
                    Toggle("Dark Text on Photo / Widget", isOn: $store.config.useDarkTextOnPhoto)
                        .onChange(of: store.config.useDarkTextOnPhoto) { _, _ in store.saveConfig() }
                    VStack(alignment: .leading) {
                        Text("Background Overlay: \(Int(store.config.bgDimOpacity * 100))%")
                            .font(.subheadline)
                        Slider(value: $store.config.bgDimOpacity, in: 0.0...0.75, step: 0.05)
                            .onChange(of: store.config.bgDimOpacity) { _, _ in store.saveConfig() }
                    }
                }

                Section("Texts") {
                    TextField("Home Title (e.g. Together for)", text: $store.config.homeTitle)
                    TextField("Widget Title (e.g. Been together 🐰)", text: $store.config.widgetTitle)
                    TextField("Widget Subtitle (e.g. GRG)", text: $store.config.widgetSubtitle)
                }

                Section("Widget Background Color") {
                    ForEach(bgPresets, id: \.1) { preset in
                        Button {
                            store.config.themeBgHex = preset.1
                            store.saveConfig()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: preset.1))
                                    .frame(width: 24, height: 24)
                                Text(preset.0)
                                    .foregroundColor(.primary)
                                Spacer()
                                if store.config.themeBgHex == preset.1 {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.pink)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Customize")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.saveConfig()
                        dismiss()
                    }
                }
            }
            .onChange(of: bgItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            store.saveImage(img, named: "background.jpg", maxDimension: 900)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Story Tab (Milestones & Memories)
struct StoryTabView: View {
    @EnvironmentObject var store: CoupleStore
    @State private var showAdd = false
    @State private var newTitle = ""
    @State private var newNote = ""
    @State private var newDate = Date()

    var body: some View {
        NavigationStack {
            List {
                Section("Milestones") {
                    ForEach(store.upcomingMilestones(), id: \.label) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.label)
                                    .font(.headline)
                                Text(item.targetDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if item.daysLeft > 0 {
                                Text("in \(item.daysLeft)d")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.pink)
                            } else if item.daysLeft == 0 {
                                Text("Today! 🎉")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }

                Section("Our Memories") {
                    if store.stories.isEmpty {
                        Text("Tap + to add your special memories.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(store.stories) { story in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(story.title).font(.headline)
                                Spacer()
                                Text(story.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !story.note.isEmpty {
                                Text(story.note)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        store.stories.remove(atOffsets: idx)
                        store.saveStories()
                    }
                }
            }
            .contentMargins(.bottom, 90, for: .scrollContent)
            .navigationTitle("Story")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $newTitle)
                        DatePicker("Date", selection: $newDate, displayedComponents: .date)
                        TextField("Note", text: $newNote, axis: .vertical)
                    }
                    .navigationTitle("New Memory")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                guard !newTitle.isEmpty else { return }
                                store.stories.insert(CoupleStory(title: newTitle, note: newNote, date: newDate), at: 0)
                                store.saveStories()
                                newTitle = ""; newNote = ""
                                showAdd = false
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAdd = false }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Memo Tab
struct MemoTabView: View {
    @EnvironmentObject var store: CoupleStore
    @State private var showAdd = false
    @State private var title = ""
    @State private var bodyText = ""

    var body: some View {
        NavigationStack {
            List {
                if store.memos.isEmpty {
                    Text("No memos yet. Tap + to write a note.")
                        .foregroundColor(.secondary)
                }
                ForEach(store.memos) { memo in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(memo.title).font(.headline)
                            Spacer()
                            Text(memo.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if !memo.body.isEmpty {
                            Text(memo.body).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { idx in
                    store.memos.remove(atOffsets: idx)
                    store.saveMemos()
                }
            }
            .contentMargins(.bottom, 90, for: .scrollContent)
            .navigationTitle("Memo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $title)
                        TextField("Write something sweet...", text: $bodyText, axis: .vertical)
                            .lineLimit(4...8)
                    }
                    .navigationTitle("New Memo")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                guard !title.isEmpty || !bodyText.isEmpty else { return }
                                store.memos.insert(CoupleMemo(title: title.isEmpty ? "Note" : title, body: bodyText), at: 0)
                                store.saveMemos()
                                title = ""; bodyText = ""
                                showAdd = false
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAdd = false }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - My / Settings Tab
struct MySettingsTabView: View {
    @EnvironmentObject var store: CoupleStore
    @StateObject private var locHelper = LocationHelper()
    @State private var p1Item: PhotosPickerItem?
    @State private var p2Item: PhotosPickerItem?
    @State private var pickingCityFor: Int? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Anniversary Date & Time") {
                    DatePicker("Together Since", selection: $store.config.startDate, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: store.config.startDate) { _, _ in
                            store.saveConfig()
                        }
                    Toggle("Include Start Day (+1)", isOn: $store.config.countInclusive)
                        .onChange(of: store.config.countInclusive) { _, _ in store.saveConfig() }
                }

                Section("Partners") {
                    TextField("Your Name", text: $store.config.partner1Name)
                        .onChange(of: store.config.partner1Name) { _, _ in store.saveConfig() }
                    PhotosPicker(selection: $p1Item, matching: .images) {
                        Label("Pick Your Avatar", systemImage: "person.crop.circle")
                    }

                    TextField("Partner Name", text: $store.config.partner2Name)
                        .onChange(of: store.config.partner2Name) { _, _ in store.saveConfig() }
                    PhotosPicker(selection: $p2Item, matching: .images) {
                        Label("Pick Partner Avatar", systemImage: "person.crop.circle.fill")
                    }
                }

                Section("Distance Between Us") {
                    Toggle("Show Distance", isOn: $store.config.showDistance)
                        .onChange(of: store.config.showDistance) { _, _ in store.saveConfig() }

                    Button {
                        pickingCityFor = 1
                    } label: {
                        HStack {
                            Text("Your City")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(store.config.city1Name)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        locHelper.requestCurrentLocation { coord in
                            store.config.city1Name = "My Location"
                            store.config.city1Lat = coord.latitude
                            store.config.city1Lon = coord.longitude
                            store.saveConfig()
                        }
                    } label: {
                        Label("Use My Current GPS Location", systemImage: "location.circle.fill")
                    }

                    Button {
                        pickingCityFor = 2
                    } label: {
                        HStack {
                            Text("Partner City")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(store.config.city2Name)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Calculated Distance")
                        Spacer()
                        Text(store.formattedDistance())
                            .bold()
                            .foregroundColor(.pink)
                    }
                }

                Section("Widgets") {
                    Button {
                        store.saveConfig()
                        WidgetCenter.shared.reloadAllTimelines()
                    } label: {
                        Label("Refresh All Widgets Now", systemImage: "arrow.clockwise")
                    }
                    HStack {
                        Text("Widget Sync (App Group)")
                        Spacer()
                        Text(store.isAppGroupAvailable ? "Connected" : "Fallback Mode")
                            .font(.caption.bold())
                            .foregroundColor(store.isAppGroupAvailable ? .green : .orange)
                    }
                    Text("The Couple v1.3 • If avatars don't appear in the widget right away, tap Refresh above or re-add the widget once.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentMargins(.bottom, 90, for: .scrollContent)
            .navigationTitle("My")
            .sheet(item: Binding(
                get: { pickingCityFor.map { PartnerSheetItem(id: $0) } },
                set: { pickingCityFor = $0?.id }
            )) { item in
                CityPickerSheet(partnerIndex: item.id)
            }
            .onChange(of: p1Item) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            store.saveImage(img, named: "avatar1.jpg", maxDimension: 400)
                        }
                    }
                }
            }
            .onChange(of: p2Item) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            store.saveImage(img, named: "avatar2.jpg", maxDimension: 400)
                        }
                    }
                }
            }
        }
    }
}

struct CityPickerSheet: View {
    @EnvironmentObject var store: CoupleStore
    @Environment(\.dismiss) var dismiss
    let partnerIndex: Int
    @State private var query: String = ""

    private var filtered: [CityPreset] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return CityPreset.presets }
        return CityPreset.presets.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.arabicName.contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { city in
                Button {
                    if partnerIndex == 1 {
                        store.config.city1Name = city.name
                        store.config.city1Lat = city.lat
                        store.config.city1Lon = city.lon
                    } else {
                        store.config.city2Name = city.name
                        store.config.city2Lat = city.lat
                        store.config.city2Lon = city.lon
                    }
                    store.saveConfig()
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(city.name).foregroundColor(.primary)
                            Text(city.arabicName).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        let current = partnerIndex == 1 ? store.config.city1Name : store.config.city2Name
                        if current == city.name {
                            Image(systemName: "checkmark").foregroundColor(.pink)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search city (e.g. الخرج / Jazan / Riyadh)")
            .navigationTitle(partnerIndex == 1 ? "Your City" : "Partner City")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
