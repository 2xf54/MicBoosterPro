import AudioToolbox
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RorViewModel: ObservableObject {
    @Published var pcHost: String = RorConfigStore.pcHost
    @Published var pcPort: String = RorConfigStore.pcPort
    @Published var pairKey: String = RorConfigStore.pairKey
    @Published var pcName: String = RorConfigStore.pcName
    @Published var isPaired: Bool = RorConfigStore.isPaired
    @Published var statusText: String = RorConfigStore.isPaired ? "Connected" : "Tap Set up a Device"
    @Published var isScanning: Bool = false
    @Published var isSyncing: Bool = false
    @Published var discoveredDevices: [RorDiscoveredDevice] = []
    @Published var textToSend: String = ""
    @Published var receivedItems: [RorReceivedEntry] = []
    @Published var chatMessages: [RorChatMessage] = []
    @Published var showSettings: Bool = false
    @Published var showSetupSheet: Bool = false
    @Published var showChatSheet: Bool = false
    @Published var showManualEntry: Bool = false
    @Published var playSounds: Bool = UserDefaults.standard.object(forKey: "ror_play_sounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(playSounds, forKey: "ror_play_sounds") }
    }

    private let historyKey = "ror_received_history"
    private let chatKey = "ror_chat_history"

    init() {
        loadHistory()
        loadChat()
        if isPaired {
            syncFromPC()
        } else {
            scanNearby()
        }
    }

    func scanNearby() {
        isScanning = true
        statusText = "Searching nearby..."
        RorDiscovery.scan(timeoutSeconds: 2.0) { [weak self] devices in
            guard let self = self else { return }
            self.isScanning = false
            self.discoveredDevices = devices
            if devices.isEmpty {
                self.statusText = self.isPaired ? "Connected" : "No nearby PCs found"
            } else {
                self.statusText = "Found \(devices.count) device(s)"
            }
        }
    }

    func connectToDevice(_ device: RorDiscoveredDevice) {
        pcHost = device.host
        pcPort = String(device.port)
        pairKey = device.pairKey
        pcName = device.deviceName

        RorConfigStore.pcHost = device.host
        RorConfigStore.pcPort = String(device.port)
        RorConfigStore.pairKey = device.pairKey
        RorConfigStore.pcName = device.deviceName
        isPaired = true
        showSetupSheet = false
        showSettings = false
        statusText = "Connected to \(device.deviceName)"
        syncFromPC()
    }

    func disconnect() {
        RorConfigStore.disconnect()
        pcHost = ""
        pcPort = "58742"
        pairKey = ""
        pcName = ""
        isPaired = false
        showSettings = false
        scanNearby()
    }

    func saveManualPairing() {
        RorConfigStore.pcHost = pcHost
        RorConfigStore.pcPort = pcPort
        RorConfigStore.pairKey = pairKey
        guard let base = RorConfigStore.baseURLString else {
            statusText = "Enter PC IP address"
            return
        }
        statusText = "Connecting..."
        RorNetwork.ping(baseURL: base) { [weak self] res in
            DispatchQueue.main.async {
                switch res {
                case .success(let name):
                    RorConfigStore.pcName = name
                    self?.pcName = name
                    self?.isPaired = true
                    self?.showSetupSheet = false
                    self?.showSettings = false
                    self?.statusText = "Connected to \(name)"
                    self?.syncFromPC()
                case .failure(let err):
                    self?.statusText = "Failed: \(err.localizedDescription)"
                }
            }
        }
    }

    func sendText() {
        let trimmed = textToSend.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textToSend = ""
        appendChat(RorChatMessage(id: UUID().uuidString, isMe: true, text: trimmed, date: Date()))
        statusText = "Sending..."
        RorNetwork.uploadText(trimmed) { [weak self] res in
            DispatchQueue.main.async {
                switch res {
                case .success:
                    self?.statusText = "Sent to \(self?.pcName.isEmpty == false ? self!.pcName : "Windows PC")"
                case .failure(let err):
                    self?.statusText = "Send failed: \(err.localizedDescription)"
                }
            }
        }
    }

    func sendBatchFiles(_ files: [(url: URL, filename: String)]) {
        guard !files.isEmpty else { return }
        let batchId = UUID().uuidString
        let total = files.count
        statusText = total == 1 ? "Sending \(files[0].filename)..." : "Sending \(total) items..."

        Task {
            var okCount = 0
            for (url, name) in files {
                let success = await withCheckedContinuation { cont in
                    RorNetwork.uploadFile(fileURL: url, filename: name, batchId: batchId, batchCount: total) { res in
                        try? FileManager.default.removeItem(at: url)
                        switch res {
                        case .success: cont.resume(returning: true)
                        case .failure: cont.resume(returning: false)
                        }
                    }
                }
                if success { okCount += 1 }
            }
            await MainActor.run {
                if okCount == total {
                    self.statusText = total == 1 ? "Sent \(files[0].filename)" : "Sent \(total) items to PC"
                } else {
                    self.statusText = "Sent \(okCount)/\(total) items"
                }
            }
        }
    }

    func sendLocalFile(_ url: URL, batchId: String? = nil, batchCount: Int = 1) {
        statusText = "Sending \(url.lastPathComponent)..."
        RorNetwork.uploadFile(fileURL: url, filename: url.lastPathComponent, batchId: batchId, batchCount: batchCount) { [weak self] res in
            DispatchQueue.main.async {
                switch res {
                case .success:
                    self?.statusText = "Sent \(url.lastPathComponent)"
                case .failure(let err):
                    self?.statusText = "Send failed: \(err.localizedDescription)"
                }
            }
        }
    }

    func syncFromPC() {
        guard let base = RorConfigStore.baseURLString,
              let url = URL(string: "\(base)/queue"),
              !RorConfigStore.pairKey.isEmpty else { return }

        isSyncing = true
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue(RorConfigStore.pairKey, forHTTPHeaderField: "X-Pair-Key")

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            if let err = err {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.statusText = "Offline: \(err.localizedDescription)"
                }
                return
            }
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(RorQueueResponse.self, from: data) else {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 401 { self.statusText = "Invalid Pair Key" }
                }
                return
            }
            if decoded.items.isEmpty {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.statusText = "Synced"
                }
                return
            }
            Task {
                for item in decoded.items {
                    await self.downloadAndSaveItem(item, baseURL: base)
                }
                await MainActor.run {
                    self.isSyncing = false
                    self.statusText = "Received \(decoded.items.count) item(s)"
                    if self.playSounds {
                        AudioServicesPlaySystemSound(1007)
                    }
                }
            }
        }.resume()
    }

    private func downloadAndSaveItem(_ item: RorQueueItem, baseURL: String) async {
        if item.type == "text" {
            let txt = item.text ?? ""
            await MainActor.run {
                UIPasteboard.general.string = txt
                self.appendChat(RorChatMessage(id: item.id, isMe: false, text: txt, date: Date()))
                self.addHistory(RorReceivedEntry(id: item.id, type: "text", title: "Text Message", detail: txt, localPath: nil, date: Date()))
            }
            await ackItem(item.id, baseURL: baseURL)
            return
        }

        guard let dlURL = URL(string: "\(baseURL)/queue/\(item.id)") else { return }
        var req = URLRequest(url: dlURL)
        req.timeoutInterval = 120
        req.setValue(RorConfigStore.pairKey, forHTTPHeaderField: "X-Pair-Key")

        do {
            let (tempURL, _) = try await URLSession.shared.download(for: req)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dest = docs.appendingPathComponent(item.filename)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)

            var detail = "Received from Windows PC"
            if item.type == "image" || item.type == "video" {
                let savedToPhotos = await saveToPhotos(url: dest, isVideo: item.type == "video")
                if savedToPhotos {
                    detail = "Saved to Photos"
                }
            }

            await MainActor.run {
                self.addHistory(RorReceivedEntry(id: item.id, type: item.type, title: item.filename, detail: detail, localPath: dest.path, date: Date()))
            }
            await ackItem(item.id, baseURL: baseURL)
        } catch {
            await MainActor.run {
                self.statusText = "Download error: \(error.localizedDescription)"
            }
        }
    }

    private func saveToPhotos(url: URL, isVideo: Bool) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }

    private func ackItem(_ id: String, baseURL: String) async {
        guard let url = URL(string: "\(baseURL)/queue/\(id)/ack") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(RorConfigStore.pairKey, forHTTPHeaderField: "X-Pair-Key")
        _ = try? await URLSession.shared.data(for: req)
    }

    private func addHistory(_ entry: RorReceivedEntry) {
        receivedItems.insert(entry, at: 0)
        if receivedItems.count > 60 { receivedItems = Array(receivedItems.prefix(60)) }
        if let data = try? JSONEncoder().encode(receivedItems) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let items = try? JSONDecoder().decode([RorReceivedEntry].self, from: data) {
            receivedItems = items
        }
    }

    private func appendChat(_ msg: RorChatMessage) {
        chatMessages.append(msg)
        if chatMessages.count > 100 { chatMessages = Array(chatMessages.suffix(100)) }
        if let data = try? JSONEncoder().encode(chatMessages) {
            UserDefaults.standard.set(data, forKey: chatKey)
        }
    }

    private func loadChat() {
        if let data = UserDefaults.standard.data(forKey: chatKey),
           let items = try? JSONDecoder().decode([RorChatMessage].self, from: data) {
            chatMessages = items
        }
    }

    func clearHistory() {
        receivedItems = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}

struct ContentView: View {
    @ObservedObject var vm: RorViewModel
    @State private var searchText: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showSendMenu = false
    @State private var shareURL: URL?

    let accent = Color(red: 1.0, green: 0.165, blue: 0.23)

    var filteredItems: [RorReceivedEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return vm.receivedItems }
        return vm.receivedItems.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q)
        }
    }

    let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Top Bar: Gear | ror | Sync
                    HStack {
                        Button {
                            vm.showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color(white: 0.14))
                                .clipShape(Circle())
                        }

                        Spacer()

                        Text("ror")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            if vm.isPaired { vm.syncFromPC() } else { vm.scanNearby() }
                        } label: {
                            Image(systemName: vm.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color(white: 0.14))
                                .clipShape(Circle())
                        }
                    }

                    // Search Bar (Blip style)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color(white: 0.55))
                        TextField("Find Received Items", text: $searchText)
                            .foregroundColor(.white)
                            .font(.system(size: 15))
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(white: 0.13))
                    .clipShape(Capsule())

                    // Device Circles Row (Blip style)
                    HStack(alignment: .top, spacing: 18) {
                        // Windows PC Circle (Tap to send)
                        Button {
                            if vm.isPaired {
                                showSendMenu = true
                            } else {
                                vm.showSetupSheet = true
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(vm.isPaired ? accent : Color(white: 0.15))
                                        .frame(width: 68, height: 68)
                                    Image(systemName: "desktopcomputer")
                                        .font(.system(size: 27, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                Text(vm.pcName.isEmpty ? "Windows PC" : vm.pcName)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Multi-Photo Send Circle
                        Button {
                            if vm.isPaired {
                                showPhotoPicker = true
                            } else {
                                vm.showSetupSheet = true
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color(white: 0.15))
                                        .frame(width: 68, height: 68)
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(accent)
                                }
                                Text("Send\nPhotos")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Chat Circle
                        Button {
                            vm.showChatSheet = true
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color(white: 0.15))
                                        .frame(width: 68, height: 68)
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 23, weight: .medium))
                                        .foregroundColor(Color(red: 0.25, green: 0.65, blue: 1.0))
                                }
                                Text("Chat")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Set up Device Circle
                        Button {
                            vm.showSetupSheet = true
                            vm.scanNearby()
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color(white: 0.15))
                                        .frame(width: 68, height: 68)
                                    Image(systemName: "laptopcomputer.and.iphone")
                                        .font(.system(size: 23, weight: .medium))
                                        .foregroundColor(Color(red: 0.25, green: 0.65, blue: 1.0))
                                }
                                Text("Set up\na Device")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Status Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(vm.isPaired ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(vm.statusText)
                            .font(.caption)
                            .foregroundColor(Color(white: 0.6))
                    }

                    // Received Section Header
                    HStack {
                        Text("Received")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        if !vm.receivedItems.isEmpty {
                            Menu {
                                Button("Clear History", role: .destructive) {
                                    vm.clearHistory()
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Color(red: 0.25, green: 0.65, blue: 1.0))
                                    .padding(8)
                            }
                        }
                    }
                    .padding(.top, 4)

                    // Received 2-Column Grid (Blip style)
                    if filteredItems.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundColor(Color(white: 0.3))
                            Text("Nothing received yet")
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.45))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(filteredItems) { item in
                                Button {
                                    if let p = item.localPath {
                                        shareURL = URL(fileURLWithPath: p)
                                    } else {
                                        UIPasteboard.general.string = item.detail
                                        vm.statusText = "Copied text"
                                    }
                                } label: {
                                    ReceivedGridCard(item: item, accent: accent)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Send to \(vm.pcName.isEmpty ? "Windows PC" : vm.pcName)", isPresented: $showSendMenu, titleVisibility: .visible) {
            Button("Photos & Videos (Multi-select)") { showPhotoPicker = true }
            Button("Files") { showFileImporter = true }
            Button("Chat / Message") { vm.showChatSheet = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems, maxSelectionCount: 0, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotoItems) { items in
            guard !items.isEmpty else { return }
            let picked = items
            selectedPhotoItems = []
            Task {
                var prepared: [(URL, String)] = []
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        let name = "ror_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4)).\(ext)"
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                        try? data.write(to: tmp)
                        prepared.append((tmp, name))
                    }
                }
                await MainActor.run {
                    vm.sendBatchFiles(prepared)
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let batchId = UUID().uuidString
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    vm.sendLocalFile(url, batchId: batchId, batchCount: urls.count)
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .sheet(isPresented: $vm.showSettings) {
            SettingsSheetView(vm: vm, accent: accent)
        }
        .sheet(isPresented: $vm.showSetupSheet) {
            SetupDeviceSheetView(vm: vm, accent: accent)
        }
        .sheet(isPresented: $vm.showChatSheet) {
            ChatSheetView(vm: vm, accent: accent)
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(activityItems: [url])
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ReceivedGridCard: View {
    let item: RorReceivedEntry
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.34), Color(white: 0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(cardPreview.clipShape(RoundedRectangle(cornerRadius: 24)))
                    .padding(.bottom, 14)

                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(item.detail)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.5))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var cardPreview: some View {
        if item.type == "image", let path = item.localPath, let uiImg = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
        } else if item.type == "text" {
            VStack {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.8))
                Text(item.detail)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                    .padding(.horizontal, 10)
            }
        } else {
            Image(systemName: item.type == "video" ? "video.fill" : "doc.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}

struct ChatSheetView: View {
    @ObservedObject var vm: RorViewModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                if vm.chatMessages.isEmpty {
                                    Text("No messages yet. Say hi to your PC!")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .padding(.top, 40)
                                }
                                ForEach(vm.chatMessages) { msg in
                                    HStack {
                                        if msg.isMe { Spacer(minLength: 50) }
                                        Text(msg.text)
                                            .font(.system(size: 15))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(msg.isMe ? accent : Color(white: 0.16))
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                        if !msg.isMe { Spacer(minLength: 50) }
                                    }
                                    .id(msg.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: vm.chatMessages.count) { _ in
                            if let last = vm.chatMessages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("Message PC...", text: $vm.textToSend)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.14))
                            .foregroundColor(.white)
                            .clipShape(Capsule())

                        Button {
                            vm.sendText()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(vm.textToSend.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : accent)
                        }
                        .disabled(vm.textToSend.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding()
                    .background(Color(white: 0.07))
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { vm.syncFromPC() } label: { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SetupDeviceSheetView: View {
    @ObservedObject var vm: RorViewModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Nearby Devices") {
                    if vm.isScanning {
                        HStack {
                            ProgressView().tint(accent)
                            Text("Scanning Wi-Fi for ror on PC...").foregroundColor(.gray)
                        }
                    } else if vm.discoveredDevices.isEmpty {
                        Text("No PCs found automatically. Make sure ror is open on PC on the same Wi-Fi.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        ForEach(vm.discoveredDevices) { dev in
                            Button {
                                vm.connectToDevice(dev)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(accent).frame(width: 36, height: 36)
                                        Image(systemName: "desktopcomputer").foregroundColor(.white).font(.caption)
                                    }
                                    VStack(alignment: .leading) {
                                        Text(dev.deviceName).foregroundColor(.white).font(.headline)
                                        Text("\(dev.host):\(dev.port)").foregroundColor(.gray).font(.caption)
                                    }
                                    Spacer()
                                    Text("Connect").foregroundColor(accent).font(.subheadline.bold())
                                }
                            }
                        }
                    }
                    Button("Scan Again") { vm.scanNearby() }.foregroundColor(accent)
                }

                Section("Manual / Tailscale") {
                    TextField("PC IP Address", text: $vm.pcHost)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("Port (58742)", text: $vm.pcPort)
                        .keyboardType(.numberPad)
                    TextField("Pair Key", text: $vm.pairKey)
                        .autocapitalization(.allCharacters)
                    Button("Save & Connect") { vm.saveManualPairing() }
                        .foregroundColor(accent)
                }
            }
            .navigationTitle("Set up a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SettingsSheetView: View {
    @ObservedObject var vm: RorViewModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Devices") {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(accent).frame(width: 34, height: 34)
                            Image(systemName: "iphone").foregroundColor(.white).font(.caption)
                        }
                        VStack(alignment: .leading) {
                            Text("iPhone").foregroundColor(.white)
                            Text("This Phone").font(.caption).foregroundColor(.gray)
                        }
                    }

                    if vm.isPaired {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(accent).frame(width: 34, height: 34)
                                Image(systemName: "desktopcomputer").foregroundColor(.white).font(.caption)
                            }
                            VStack(alignment: .leading) {
                                Text(vm.pcName.isEmpty ? "Windows PC" : vm.pcName).foregroundColor(.white)
                                Text("Computer").font(.caption).foregroundColor(.gray)
                            }
                        }
                    }

                    Button("Set up Another Device") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            vm.showSetupSheet = true
                            vm.scanNearby()
                        }
                    }
                    .foregroundColor(.blue)
                }

                Section("Preferences") {
                    Toggle("Play Sound Effects", isOn: $vm.playSounds)
                        .tint(.green)
                }

                if vm.isPaired {
                    Section {
                        Button("Disconnect PC", role: .destructive) {
                            vm.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
