import AudioToolbox
import AVFoundation
import AVKit
import Photos
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

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
    private var audioPlayer: AVAudioPlayer?
    private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
    private var bgTimer: Timer?

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
        let msgId = UUID().uuidString
        appendChat(RorChatMessage(id: msgId, isMe: true, text: text, date: Date()))
        RorSiriShareDonor.donateWindowsPC()
        statusText = "Sending..."
        RorNetwork.uploadText(text, messageId: msgId) { [weak self] res in
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

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sentDir = docs.appendingPathComponent("ror_sent", isDirectory: true)
        try? FileManager.default.createDirectory(at: sentDir, withIntermediateDirectories: true)

        var msgIds: [String] = []
        for (idx, item) in files.enumerated() {
            let mtype = idx < mediaTypes.count ? mediaTypes[idx] : "file"
            var savedLocalPath: String? = nil
            if mtype == "image" || mtype == "video" {
                let dest = sentDir.appendingPathComponent(item.filename)
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: item.url, to: dest)) != nil {
                    savedLocalPath = dest.path
                }
            }
            let mid = UUID().uuidString
            msgIds.append(mid)
            appendChat(RorChatMessage(id: mid, isMe: true, text: item.filename, date: Date(), localPath: savedLocalPath, mediaType: mtype))
        }

        Task {
            var okCount = 0
            for (idx, (url, name)) in files.enumerated() {
                let mid = idx < msgIds.count ? msgIds[idx] : nil
                let success = await withCheckedContinuation { cont in
                    RorNetwork.uploadFile(fileURL: url, filename: name, batchId: batchId, batchCount: total, messageId: mid) { res in
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
        let mid = UUID().uuidString
        appendChat(RorChatMessage(id: mid, isMe: true, text: url.lastPathComponent, date: Date(), localPath: nil, mediaType: "file"))
        RorNetwork.uploadFile(fileURL: url, filename: url.lastPathComponent, batchId: batchId, batchCount: batchCount, messageId: mid) { [weak self] res in
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
                var normalItems: [RorQueueItem] = []
                for item in decoded.items {
                    if item.type == "delete" {
                        if let raw = item.text?.data(using: .utf8),
                           let delIds = try? JSONDecoder().decode([String].self, from: raw) {
                            await MainActor.run {
                                self.removeMessagesLocally(ids: Set(delIds))
                            }
                        }
                        await self.ackItem(item.id, baseURL: base)
                    } else {
                        normalItems.append(item)
                        await self.downloadAndSaveItem(item, baseURL: base)
                    }
                }
                await MainActor.run {
                    self.isSyncing = false
                    if !normalItems.isEmpty {
                        self.statusText = "Received \(normalItems.count) item(s)"
                        if UIApplication.shared.applicationState != .active {
                            Self.postLocalNotification(
                                body: Self.formatNotificationBody(for: normalItems),
                                playSound: self.playSounds
                            )
                        } else if self.playSounds {
                            self.playChime()
                        }
                    }
                }
            }
        }.resume()
    }

    func startBackgroundPolling() {
        guard isPaired, bgTaskId == .invalid else { return }
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "ror.bg.sync") { [weak self] in
            self?.endBackgroundPolling()
        }
        bgTimer?.invalidate()
        bgTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromPC(silent: true)
            }
        }
    }

    func endBackgroundPolling() {
        bgTimer?.invalidate()
        bgTimer = nil
        if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = .invalid
        }
    }

    static func performBackgroundSync() async -> Bool {
        guard let base = RorConfigStore.baseURLString,
              let url = URL(string: "\(base)/queue"),
              !RorConfigStore.pairKey.isEmpty else { return false }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(RorConfigStore.pairKey, forHTTPHeaderField: "X-Pair-Key")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let decoded = try? JSONDecoder().decode(RorQueueResponse.self, from: data),
              !decoded.items.isEmpty else {
            return true
        }

        let playSounds = UserDefaults.standard.object(forKey: "ror_play_sounds") as? Bool ?? true
        postLocalNotification(body: formatNotificationBody(for: decoded.items), playSound: playSounds)
        return true
    }

    static func formatNotificationBody(for items: [RorQueueItem]) -> String {
        let images = items.filter { $0.type == "image" }.count
        let videos = items.filter { $0.type == "video" }.count
        let texts = items.filter { $0.type == "text" }.count
        let files = items.filter { $0.type != "image" && $0.type != "video" && $0.type != "text" }.count

        var parts: [String] = []
        if images > 0 { parts.append(images == 1 ? "1 photo" : "\(images) photos") }
        if videos > 0 { parts.append(videos == 1 ? "1 video" : "\(videos) videos") }
        if files > 0 {
            if files == 1, let fn = items.first(where: { $0.type != "image" && $0.type != "video" && $0.type != "text" })?.filename {
                parts.append(fn)
            } else {
                parts.append("\(files) files")
            }
        }
        if texts > 0 {
            if items.count == 1, let t = items.first?.text, !t.isEmpty {
                parts.append(t)
            } else {
                parts.append(texts == 1 ? "1 message" : "\(texts) messages")
            }
        }
        return parts.isEmpty ? "New item" : parts.joined(separator: ", ")
    }

    static func postLocalNotification(body: String, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Windows PC"
        content.body = body
        if playSound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("notify.wav"))
        }
        let req = UNNotificationRequest(
            identifier: "ror_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func playChime() {
        guard let url = Bundle.main.url(forResource: "notify", withExtension: "wav") else {
            AudioServicesPlaySystemSound(1007)
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            AudioServicesPlaySystemSound(1007)
        }
    }

    private func downloadAndSaveItem(_ item: RorQueueItem, baseURL: String) async {
        if item.type == "text" {
            let txt = item.text ?? ""
            await MainActor.run {
                UIPasteboard.general.string = txt
                self.appendChat(RorChatMessage(id: item.id, isMe: false, text: txt, date: Date()))
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
            receivedItems = items.filter { $0.type != "text" }
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

    func deleteItem(_ item: RorReceivedEntry) {
        if let p = item.localPath {
            try? FileManager.default.removeItem(atPath: p)
        }
        receivedItems.removeAll { $0.id == item.id }
        if let data = try? JSONEncoder().encode(receivedItems) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func removeMessagesLocally(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        chatMessages.removeAll { ids.contains($0.id) }
        if let data = try? JSONEncoder().encode(chatMessages) {
            UserDefaults.standard.set(data, forKey: chatKey)
        }
        receivedItems.removeAll { ids.contains($0.id) }
        if let data = try? JSONEncoder().encode(receivedItems) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func deleteChatMessages(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        removeMessagesLocally(ids: ids)
        RorNetwork.deleteMessages(ids: Array(ids))
    }

    func deleteReceivedItems(ids: Set<String>) {
        for item in receivedItems where ids.contains(item.id) {
            if let p = item.localPath {
                try? FileManager.default.removeItem(atPath: p)
            }
        }
        receivedItems.removeAll { ids.contains($0.id) }
        if let data = try? JSONEncoder().encode(receivedItems) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func copyReceivedItem(_ item: RorReceivedEntry) {
        if let p = item.localPath {
            if item.type == "image", let img = UIImage(contentsOfFile: p) {
                UIPasteboard.general.image = img
                statusText = "Copied image"
            } else {
                UIPasteboard.general.url = URL(fileURLWithPath: p)
                statusText = "Copied \(item.title)"
            }
        } else {
            UIPasteboard.general.string = item.detail
            statusText = "Copied text"
        }
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
    @State private var quickLookURL: URL?
    @State private var videoPlayerURL: URL?
    @State private var isSelectingReceived = false
    @State private var selectedReceivedIds: Set<String> = []

    let accent = Color(red: 1.0, green: 0.165, blue: 0.23)
    let autoSyncTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var filteredItems: [RorReceivedEntry] {
        let mediaOnly = vm.receivedItems.filter { $0.type != "text" }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return mediaOnly }
        return mediaOnly.filter {
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
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isSelectingReceived.toggle()
                                if !isSelectingReceived {
                                    selectedReceivedIds.removeAll()
                                }
                            }
                        } label: {
                            if isSelectingReceived {
                                Text("Done")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .background(accent)
                                    .clipShape(Capsule())
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color(white: 0.14))
                                    .clipShape(Circle())
                            }
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
                                    if isSelectingReceived {
                                        if selectedReceivedIds.contains(item.id) {
                                            selectedReceivedIds.remove(item.id)
                                        } else {
                                            selectedReceivedIds.insert(item.id)
                                        }
                                    } else if let u = resolveLocalURL(path: item.localPath, filename: item.title) {
                                        if item.type == "video" {
                                            videoPlayerURL = u
                                        } else {
                                            quickLookURL = u
                                        }
                                    } else {
                                        UIPasteboard.general.string = item.detail
                                        vm.statusText = "Copied text"
                                    }
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        ReceivedGridCard(item: item, accent: accent)
                                            .opacity(isSelectingReceived && !selectedReceivedIds.contains(item.id) ? 0.72 : 1.0)
                                        if isSelectingReceived {
                                            let isSel = selectedReceivedIds.contains(item.id)
                                            Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 22, weight: .semibold))
                                                .foregroundColor(isSel ? accent : .white.opacity(0.85))
                                                .background(Circle().fill(Color.black.opacity(0.55)))
                                                .padding(10)
                                        }
                                    }
                                }
                                .contextMenu {
                                    if let p = item.localPath {
                                        Button {
                                            quickLookURL = URL(fileURLWithPath: p)
                                        } label: {
                                            Label("Quick Look", systemImage: "eye")
                                        }
                                    }
                                    Button {
                                        vm.copyReceivedItem(item)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    if let p = item.localPath {
                                        Button {
                                            shareURL = URL(fileURLWithPath: p)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        vm.deleteItem(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, isSelectingReceived ? 90 : 30)
            }

            if isSelectingReceived {
                VStack {
                    Spacer()
                    HStack(spacing: 14) {
                        Button {
                            if selectedReceivedIds.count == filteredItems.count {
                                selectedReceivedIds.removeAll()
                            } else {
                                selectedReceivedIds = Set(filteredItems.map { $0.id })
                            }
                        } label: {
                            Text(selectedReceivedIds.count == filteredItems.count && !filteredItems.isEmpty ? "Deselect All" : "Select All")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .background(Color(white: 0.18))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Button(role: .destructive) {
                            vm.deleteReceivedItems(ids: selectedReceivedIds)
                            selectedReceivedIds.removeAll()
                            isSelectingReceived = false
                        } label: {
                            Label("Delete (\(selectedReceivedIds.count))", systemImage: "trash.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                                .background(selectedReceivedIds.isEmpty ? Color(white: 0.25) : accent)
                                .clipShape(Capsule())
                        }
                        .disabled(selectedReceivedIds.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .sheet(item: $videoPlayerURL) { url in
            VideoPlayerSheet(url: url)
        }
        .quickLookPreview($quickLookURL)
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
                Color(white: 0.16)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        cardPreview
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        let resolved = resolveLocalURL(path: item.localPath, filename: item.title)
        let ext = (item.title as NSString).pathExtension.lowercased()
        let isImg = item.type == "image" || ["png", "jpg", "jpeg", "webp", "heic", "gif"].contains(ext)
        let isVid = item.type == "video" || ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)

        if isImg, let u = resolved, let uiImg = UIImage(contentsOfFile: u.path) {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
        } else if isVid, let u = resolved {
            VideoThumbnailView(url: u)
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
            FileBubbleCard(filename: item.title, isGrid: true)
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
    @State private var videoPlayerURL: URL?
    @State private var isSelectingChat = false
    @State private var selectedChatIds: Set<String> = []

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
                                    HStack(spacing: 8) {
                                        if isSelectingChat {
                                            let isSel = selectedChatIds.contains(msg.id)
                                            Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 22))
                                                .foregroundColor(isSel ? accent : .gray)
                                                .onTapGesture {
                                                    if isSel { selectedChatIds.remove(msg.id) } else { selectedChatIds.insert(msg.id) }
                                                }
                                        }
                                        if msg.isMe { Spacer(minLength: 50) }
                                        chatBubble(msg)
                                            .onTapGesture {
                                                if isSelectingChat {
                                                    if selectedChatIds.contains(msg.id) { selectedChatIds.remove(msg.id) } else { selectedChatIds.insert(msg.id) }
                                                } else if msg.mediaType == nil {
                                                    if let url = detectURL(in: msg.text) {
                                                        UIApplication.shared.open(url)
                                                    } else {
                                                        UIPasteboard.general.string = msg.text
                                                        showToast("Copy ✓")
                                                    }
                                                } else if let u = resolveLocalURL(path: msg.localPath, filename: msg.text) {
                                                    if msg.mediaType == "video" {
                                                        videoPlayerURL = u
                                                    } else {
                                                        shareFileURL = u
                                                    }
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
                                                if let u = resolveLocalURL(path: msg.localPath, filename: msg.text) {
                                                    if msg.mediaType == "image" || msg.mediaType == "video" {
                                                        Button {
                                                            vm.saveMediaToPhotos(path: u.path, isVideo: msg.mediaType == "video") { ok in
                                                                showToast(ok ? "Saved ✓" : "Failed")
                                                            }
                                                        } label: {
                                                            Label("Save", systemImage: "square.and.arrow.down")
                                                        }
                                                    } else {
                                                        Button {
                                                            shareFileURL = u
                                                        } label: {
                                                            Label("Save / Share", systemImage: "square.and.arrow.up")
                                                        }
                                                    }
                                                }
                                                Button {
                                                    if msg.mediaType == "image",
                                                       let u = resolveLocalURL(path: msg.localPath, filename: msg.text),
                                                       let img = UIImage(contentsOfFile: u.path) {
                                                        UIPasteboard.general.image = img
                                                    } else {
                                                        UIPasteboard.general.string = msg.text
                                                    }
                                                    showToast("Copy ✓")
                                                } label: {
                                                    Label("Copy", systemImage: "doc.on.doc")
                                                }
                                                Button(role: .destructive) {
                                                    vm.deleteChatMessages(ids: [msg.id])
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
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

                    if isSelectingChat {
                        HStack(spacing: 14) {
                            Button {
                                if selectedChatIds.count == vm.chatMessages.count {
                                    selectedChatIds.removeAll()
                                } else {
                                    selectedChatIds = Set(vm.chatMessages.map { $0.id })
                                }
                            } label: {
                                Text(selectedChatIds.count == vm.chatMessages.count && !vm.chatMessages.isEmpty ? "Deselect All" : "Select All")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .background(Color(white: 0.18))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Button(role: .destructive) {
                                vm.deleteChatMessages(ids: selectedChatIds)
                                selectedChatIds.removeAll()
                                isSelectingChat = false
                            } label: {
                                Label("Delete (\(selectedChatIds.count))", systemImage: "trash.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .frame(height: 40)
                                    .background(selectedChatIds.isEmpty ? Color(white: 0.25) : accent)
                                    .clipShape(Capsule())
                            }
                            .disabled(selectedChatIds.isEmpty)
                        }
                        .padding()
                        .background(Color(white: 0.07))
                    } else {
                        // Bottom Chat Input with + Attach Menu on the left
                        HStack(spacing: 10) {
                        Menu {
                            Button {
                                showChatPhotos = true
                            } label: {
                                Label("Photos & Videos", systemImage: "photo.on.rectangle.angled")
                            }
                            Button {
                                showChatFiles = true
                            } label: {
                                Label("Files", systemImage: "folder")
                            }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelectingChat ? "Cancel" : "Select") {
                        isSelectingChat.toggle()
                        if !isSelectingChat { selectedChatIds.removeAll() }
                    }
                    .foregroundColor(isSelectingChat ? accent : .white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
            .sheet(item: $videoPlayerURL) { url in
                VideoPlayerSheet(url: url)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func chatBubble(_ msg: RorChatMessage) -> some View {
        let resolved = resolveLocalURL(path: msg.localPath, filename: msg.text)
        if let u = resolved, msg.mediaType == "image", let img = UIImage(contentsOfFile: u.path) {
            VStack(alignment: .leading, spacing: 4) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 210, height: 185)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Hold to Save")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(6)
            .background(msg.isMe ? accent : Color(white: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if let u = resolved, msg.mediaType == "video" {
            VStack(alignment: .leading, spacing: 4) {
                VideoThumbnailView(url: u)
                    .frame(width: 210, height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Tap to Play • Hold to Save")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(6)
            .background(msg.isMe ? accent : Color(white: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if msg.mediaType != nil {
            FileBubbleCard(filename: msg.text, isGrid: false)
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
        if t.hasPrefix("["), let closeBracket = t.firstIndex(of: "]"), t.contains("://") {
            return String(t[t.index(after: t.startIndex)..<closeBracket])
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelectingChat ? "Cancel" : "Select") {
                        isSelectingChat.toggle()
                        if !isSelectingChat { selectedChatIds.removeAll() }
                    }
                    .foregroundColor(isSelectingChat ? accent : .white)
                }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelectingChat ? "Cancel" : "Select") {
                        isSelectingChat.toggle()
                        if !isSelectingChat { selectedChatIds.removeAll() }
                    }
                    .foregroundColor(isSelectingChat ? accent : .white)
                }
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


struct VideoThumbnailView: View {
    let url: URL
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(white: 0.12)
            }

            Circle()
                .fill(Color.black.opacity(0.62))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: 2)
                )
        }
        .clipped()
        .task(id: url.path) {
            thumbnail = await Self.generateThumbnail(for: url)
        }
    }

    private static func generateThumbnail(for url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .positiveInfinity
            gen.maximumSize = CGSize(width: 480, height: 480)
            if let cgImg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
                return UIImage(cgImage: cgImg)
            }
            return nil
        }.value
    }
}

func resolveLocalURL(path: String?, filename: String) -> URL? {
    let fm = FileManager.default
    if let p = path, !p.isEmpty, fm.fileExists(atPath: p) {
        return URL(fileURLWithPath: p)
    }
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let direct = docs.appendingPathComponent(filename)
    if fm.fileExists(atPath: direct.path) {
        return direct
    }
    let sent = docs.appendingPathComponent("ror_sent", isDirectory: true).appendingPathComponent(filename)
    if fm.fileExists(atPath: sent.path) {
        return sent
    }
    return nil
}

struct VideoPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AVPlayerRepresentable(url: url)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
    }
}

struct AVPlayerRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
    }
}

struct FileBubbleCard: View {
    let filename: String
    let isGrid: Bool

    private var fileExt: String {
        let ext = (filename as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : String(ext.prefix(5))
    }

    var body: some View {
        if isGrid {
            VStack(spacing: 10) {
                ZStack(alignment: .bottom) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 46))
                        .foregroundColor(Color(white: 0.88))
                    Text(fileExt)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 1.0, green: 0.165, blue: 0.23))
                        .clipShape(Capsule())
                        .offset(y: 6)
                }
            }
        } else {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 42, height: 48)
                    VStack(spacing: 2) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                        Text(fileExt)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text("Tap to Open / Save")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
