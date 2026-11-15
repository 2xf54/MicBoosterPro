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
    @Published var showWindowsPCSheet: Bool = false
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
            RorSiriShareDonor.donateWindowsPC()
            syncFromPC(silent: true)
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
        statusText = "Connected to Windows PC"
        RorSiriShareDonor.donateWindowsPC()
        syncFromPC(silent: true)
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
                    self?.statusText = "Connected to Windows PC"
                    RorSiriShareDonor.donateWindowsPC()
                    self?.syncFromPC(silent: true)
                case .failure(let err):
                    self?.statusText = "Failed: \(err.localizedDescription)"
                }
            }
        }
    }

    func pasteFromClipboard() {
        if let img = UIPasteboard.general.image, let data = img.jpegData(compressionQuality: 0.92) {
            let name = "paste_\(Int(Date().timeIntervalSince1970)).jpg"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? data.write(to: tmp)
            sendBatchFiles([(tmp, name)], mediaTypes: ["image"])
            return
        }
        if let txt = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !txt.isEmpty {
            sendTextValue(txt)
            return
        }
        statusText = "Clipboard is empty"
    }

    func sendText() {
        let trimmed = textToSend.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textToSend = ""
        sendTextValue(trimmed)
    }

    func sendTextValue(_ text: String) {
        appendChat(RorChatMessage(id: UUID().uuidString, isMe: true, text: text, date: Date()))
        RorSiriShareDonor.donateWindowsPC()
        statusText = "Sending..."
        RorNetwork.uploadText(text) { [weak self] res in
            DispatchQueue.main.async {
                switch res {
                case .success:
                    self?.statusText = "Sent to Windows PC"
                case .failure(let err):
                    self?.statusText = "Send failed: \(err.localizedDescription)"
                }
            }
        }
    }

    func sendBatchFiles(_ files: [(url: URL, filename: String)], mediaTypes: [String] = []) {
        guard !files.isEmpty else { return }
        let batchId = UUID().uuidString
        let total = files.count
        statusText = total == 1 ? "Sending \(files[0].filename)..." : "Sending \(total) items..."
        RorSiriShareDonor.donateWindowsPC()

        for (idx, item) in files.enumerated() {
            let mtype = idx < mediaTypes.count ? mediaTypes[idx] : "file"
            appendChat(RorChatMessage(id: UUID().uuidString, isMe: true, text: item.filename, date: Date(), localPath: nil, mediaType: mtype))
        }

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
        RorSiriShareDonor.donateWindowsPC()
        appendChat(RorChatMessage(id: UUID().uuidString, isMe: true, text: url.lastPathComponent, date: Date(), localPath: nil, mediaType: "file"))
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

    func syncFromPC(silent: Bool = false) {
        guard !isSyncing,
              let base = RorConfigStore.baseURLString,
              let url = URL(string: "\(base)/queue"),
              !RorConfigStore.pairKey.isEmpty else { return }

        isSyncing = true
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue(RorConfigStore.pairKey, forHTTPHeaderField: "X-Pair-Key")

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            if let err = err {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    if !silent { self.statusText = "Offline: \(err.localizedDescription)" }
                }
                return
            }
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(RorQueueResponse.self, from: data) else {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 401 && !silent { self.statusText = "Invalid Pair Key" }
                }
                return
            }
            if decoded.items.isEmpty {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    if !silent { self.statusText = "Synced" }
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
                self.appendChat(RorChatMessage(id: item.id, isMe: false, text: item.filename, date: Date(), localPath: dest.path, mediaType: item.type))
                self.addHistory(RorReceivedEntry(id: item.id, type: item.type, title: item.filename, detail: detail, localPath: dest.path, date: Date()))
            }
            await ackItem(item.id, baseURL: baseURL)
        } catch {
            await MainActor.run {
                self.statusText = "Download error: \(error.localizedDescription)"
            }
        }
    }

    func saveMediaToPhotos(path: String, isVideo: Bool, completion: @escaping (Bool) -> Void) {
        let url = URL(fileURLWithPath: path)
        Task {
            let ok = await saveToPhotos(url: url, isVideo: isVideo)
            await MainActor.run { completion(ok) }
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var shareURL: URL?

    let accent = Color(red: 1.0, green: 0.165, blue: 0.23)
    let autoSyncTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

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
                    // Top Bar: Gear | Rg | Sync
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

                        Text("Rg")
                            .font(.system(size: 20, weight: .bold))
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

                    // Search Bar
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

                    // Device Circles Row
                    HStack(alignment: .top, spacing: 18) {
                        // Windows PC Circle (Tap to open Blip-style action sheet)
                        Button {
                            if vm.isPaired {
                                vm.showWindowsPCSheet = true
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
                                Text("Windows PC")
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
                                        .foregroundColor(accent)
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
                                    .foregroundColor(accent)
                                    .padding(8)
                            }
                        }
                    }
                    .padding(.top, 4)

                    // Received 2-Column Grid
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
        .onReceive(autoSyncTimer) { _ in
            if scenePhase == .active && vm.isPaired {
                vm.syncFromPC(silent: true)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems, maxSelectionCount: 0, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotoItems) { items in
            guard !items.isEmpty else { return }
            let picked = items
            selectedPhotoItems = []
            Task {
                var prepared: [(URL, String)] = []
                var mtypes: [String] = []
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let ut = item.supportedContentTypes.first
                        let ext = ut?.preferredFilenameExtension ?? "jpg"
                        let isVid = ut?.conforms(to: .movie) == true || ut?.conforms(to: .video) == true
                        let name = "ror_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4)).\(ext)"
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                        try? data.write(to: tmp)
                        prepared.append((tmp, name))
                        mtypes.append(isVid ? "video" : "image")
                    }
                }
                await MainActor.run {
                    vm.sendBatchFiles(prepared, mediaTypes: mtypes)
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
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.92) {
                    let name = "cam_\(Int(Date().timeIntervalSince1970)).jpg"
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try? data.write(to: tmp)
                    vm.sendBatchFiles([(tmp, name)], mediaTypes: ["image"])
                }
            }
        }
        .sheet(isPresented: $vm.showWindowsPCSheet) {
            WindowsPCSheetView(
                vm: vm,
                accent: accent,
                onPaste: { vm.pasteFromClipboard() },
                onSendPhotos: { showPhotoPicker = true },
                onSendFiles: { showFileImporter = true },
                onCapturePhoto: { showCamera = true },
                onOpenChat: { vm.showChatSheet = true }
            )
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

struct WindowsPCSheetView: View {
    @ObservedObject var vm: RorViewModel
    let accent: Color
    let onPaste: () -> Void
    let onSendPhotos: () -> Void
    let onSendFiles: () -> Void
    let onCapturePhoto: () -> Void
    let onOpenChat: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color(white: 0.18))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 84, height: 84)
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.top, 8)

                Text("Windows PC")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 12)

                Text("Your computer")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .padding(.top, 2)

                Divider()
                    .background(Color(white: 0.2))
                    .padding(.vertical, 22)
                    .padding(.horizontal, 20)

                VStack(spacing: 18) {
                    sheetRow(icon: "doc.on.clipboard.fill", color: Color(red: 0.18, green: 0.78, blue: 0.45), title: "Paste") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onPaste() }
                    }
                    sheetRow(icon: "photo.fill", color: accent, title: "Send Photos") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onSendPhotos() }
                    }
                    sheetRow(icon: "folder.fill", color: Color(red: 1.0, green: 0.42, blue: 0.28), title: "Send Files") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onSendFiles() }
                    }
                    sheetRow(icon: "camera.fill", color: Color(white: 0.48), title: "Capture a Photo") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onCapturePhoto() }
                    }
                    sheetRow(icon: "bubble.left.and.bubble.right.fill", color: Color(red: 0.25, green: 0.65, blue: 1.0), title: "Open Chat") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onOpenChat() }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func sheetRow(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }
        }
    }
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
    @State private var showAttachMenu = false
    @State private var showChatPhotos = false
    @State private var showChatFiles = false
    @State private var chatPhotoItems: [PhotosPickerItem] = []
    @State private var toastText: String? = nil
    @State private var shareFileURL: URL?

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
                                        chatBubble(msg)
                                            .onTapGesture {
                                                if msg.mediaType == nil {
                                                    if let url = detectURL(in: msg.text) {
                                                        UIApplication.shared.open(url)
                                                    } else {
                                                        UIPasteboard.general.string = msg.text
                                                        showToast("Copy ✓")
                                                    }
                                                } else if let p = msg.localPath {
                                                    shareFileURL = URL(fileURLWithPath: p)
                                                }
                                            }
                                            .contextMenu {
                                                if msg.mediaType == nil, let url = detectURL(in: msg.text) {
                                                    Button {
                                                        UIApplication.shared.open(url)
                                                    } label: {
                                                        Label("Open in Safari", systemImage: "safari")
                                                    }
                                                }
                                                if let p = msg.localPath {
                                                    if msg.mediaType == "image" || msg.mediaType == "video" {
                                                        Button {
                                                            vm.saveMediaToPhotos(path: p, isVideo: msg.mediaType == "video") { ok in
                                                                showToast(ok ? "Saved ✓" : "Failed")
                                                            }
                                                        } label: {
                                                            Label("Save", systemImage: "square.and.arrow.down")
                                                        }
                                                    } else {
                                                        Button {
                                                            shareFileURL = URL(fileURLWithPath: p)
                                                        } label: {
                                                            Label("Save / Share", systemImage: "square.and.arrow.up")
                                                        }
                                                    }
                                                }
                                                Button {
                                                    UIPasteboard.general.string = msg.text
                                                    showToast("Copy ✓")
                                                } label: {
                                                    Label("Copy", systemImage: "doc.on.doc")
                                                }
                                            }
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

                    // Bottom Chat Input with + Attach button on the left
                    HStack(spacing: 10) {
                        Button {
                            showAttachMenu = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color(white: 0.16))
                                .clipShape(Circle())
                        }

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

                if let t = toastText {
                    VStack {
                        Text(t)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .clipShape(Capsule())
                            .padding(.top, 14)
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Attach to Chat", isPresented: $showAttachMenu) {
                Button("Photos & Videos") { showChatPhotos = true }
                Button("Files") { showChatFiles = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showChatPhotos, selection: $chatPhotoItems, maxSelectionCount: 0, matching: .any(of: [.images, .videos]))
            .onChange(of: chatPhotoItems) { items in
                guard !items.isEmpty else { return }
                let picked = items
                chatPhotoItems = []
                Task {
                    var prepared: [(URL, String)] = []
                    var mtypes: [String] = []
                    for item in picked {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let ut = item.supportedContentTypes.first
                            let ext = ut?.preferredFilenameExtension ?? "jpg"
                            let isVid = ut?.conforms(to: .movie) == true || ut?.conforms(to: .video) == true
                            let name = "ror_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4)).\(ext)"
                            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                            try? data.write(to: tmp)
                            prepared.append((tmp, name))
                            mtypes.append(isVid ? "video" : "image")
                        }
                    }
                    await MainActor.run {
                        vm.sendBatchFiles(prepared, mediaTypes: mtypes)
                    }
                }
            }
            .fileImporter(isPresented: $showChatFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    let batchId = UUID().uuidString
                    for url in urls {
                        let accessed = url.startAccessingSecurityScopedResource()
                        vm.sendLocalFile(url, batchId: batchId, batchCount: urls.count)
                        if accessed { url.stopAccessingSecurityScopedResource() }
                    }
                }
            }
            .sheet(item: $shareFileURL) { url in
                ShareSheet(activityItems: [url])
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func chatBubble(_ msg: RorChatMessage) -> some View {
        if let path = msg.localPath, msg.mediaType == "image", let img = UIImage(contentsOfFile: path) {
            VStack(alignment: .leading, spacing: 4) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 210, maxHeight: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Hold to Save")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(6)
            .background(msg.isMe ? accent : Color(white: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if msg.mediaType != nil {
            HStack(spacing: 8) {
                Image(systemName: msg.mediaType == "video" ? "video.fill" : "doc.fill")
                Text(msg.text)
                    .lineLimit(1)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(msg.isMe ? accent : Color(white: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            let cleanText = cleanMessageText(msg.text)
            let isLink = detectURL(in: cleanText) != nil
            Text(cleanText)
                .font(.system(size: 15))
                .foregroundColor(isLink ? Color(red: 0.42, green: 0.75, blue: 1.0) : .white)
                .underline(isLink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(msg.isMe ? accent : Color(white: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func cleanMessageText(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<") && t.hasSuffix(">") && t.contains("://") {
            return String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func detectURL(in text: String) -> URL? {
        let cleaned = cleanMessageText(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        return detector.firstMatch(in: cleaned, options: [], range: range)?.url
    }

    private func showToast(_ text: String) {
        withAnimation { toastText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                if toastText == text { toastText = nil }
            }
        }
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
                                Text("Windows PC").foregroundColor(.white)
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

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onCapture(img)
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
