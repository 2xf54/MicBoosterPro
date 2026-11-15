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
    @Published var statusText: String = RorConfigStore.isPaired ? "Connected to \(RorConfigStore.pcName.isEmpty ? RorConfigStore.pcHost : RorConfigStore.pcName)" : "Scanning nearby devices..."
    @Published var isScanning: Bool = false
    @Published var isSyncing: Bool = false
    @Published var discoveredDevices: [RorDiscoveredDevice] = []
    @Published var textToSend: String = ""
    @Published var receivedItems: [RorReceivedEntry] = []
    @Published var showSettings: Bool = false
    @Published var showManualEntry: Bool = false

    private let historyKey = "ror_received_history"

    init() {
        loadHistory()
        if isPaired {
            syncFromPC()
        } else {
            scanNearby()
        }
    }

    func scanNearby() {
        isScanning = true
        statusText = "Searching nearby devices..."
        RorDiscovery.scan(timeoutSeconds: 2.0) { [weak self] devices in
            guard let self = self else { return }
            self.isScanning = false
            self.discoveredDevices = devices
            if devices.isEmpty {
                self.statusText = "No nearby PCs found. Make sure ror is open on PC."
            } else {
                self.statusText = "Found \(devices.count) device(s) nearby"
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
        statusText = "Connecting to PC..."
        RorNetwork.ping(baseURL: base) { [weak self] res in
            DispatchQueue.main.async {
                switch res {
                case .success(let name):
                    RorConfigStore.pcName = name
                    self?.pcName = name
                    self?.isPaired = true
                    self?.showSettings = false
                    self?.statusText = "Connected to \(name)"
                    self?.syncFromPC()
                case .failure(let err):
                    self?.statusText = "Connection failed: \(err.localizedDescription)"
                }
            }
        }
    }

    func sendText() {
        let trimmed = textToSend.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        statusText = "Sending text..."
        RorNetwork.uploadText(trimmed) { [weak self] res in
            DispatchQueue.main.async {
                switch res {
                case .success:
                    self?.textToSend = ""
                    self?.statusText = "Text sent to \(self?.pcName.isEmpty == false ? self!.pcName : "PC")"
                case .failure(let err):
                    self?.statusText = "Send failed: \(err.localizedDescription)"
                }
            }
        }
    }

    func sendLocalFile(_ url: URL) {
        statusText = "Sending \(url.lastPathComponent)..."
        RorNetwork.uploadFile(fileURL: url, filename: url.lastPathComponent) { [weak self] res in
            DispatchQueue.main.async {
                switch res {
                case .success:
                    self?.statusText = "Sent \(url.lastPathComponent) to \(self?.pcName.isEmpty == false ? self!.pcName : "PC")"
                case .failure(let err):
                    self?.statusText = "Send failed: \(err.localizedDescription)"
                }
            }
        }
    }

    func syncFromPC() {
        guard isPaired,
              let base = RorConfigStore.baseURLString,
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
            let displayName = self.pcName.isEmpty ? self.pcHost : self.pcName
            if decoded.items.isEmpty {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.statusText = "Connected to \(displayName)"
                }
                return
            }
            Task {
                for item in decoded.items {
                    await self.downloadAndSaveItem(item, baseURL: base)
                }
                await MainActor.run {
                    self.isSyncing = false
                    self.statusText = "Received \(decoded.items.count) item(s) from \(displayName)"
                }
            }
        }.resume()
    }

    private func downloadAndSaveItem(_ item: RorQueueItem, baseURL: String) async {
        if item.type == "text" {
            let txt = item.text ?? ""
            await MainActor.run {
                UIPasteboard.general.string = txt
                self.addHistory(RorReceivedEntry(id: item.id, type: "text", title: "Text Message (Copied)", detail: txt, localPath: nil, date: Date()))
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

            var detail = "Saved in Files (ror)"
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
        if receivedItems.count > 50 { receivedItems = Array(receivedItems.prefix(50)) }
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
}

struct ContentView: View {
    @ObservedObject var vm: RorViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter = false

    let accent = Color(red: 1.0, green: 0.165, blue: 0.23)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        HStack(spacing: 12) {
                            Text("R")
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(accent)
                                .frame(width: 44, height: 44)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.4), lineWidth: 1))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("ror")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Text(vm.statusText)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                if vm.isPaired { vm.syncFromPC() } else { vm.scanNearby() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(accent)
                                    .padding(10)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Circle())
                            }
                            Button {
                                vm.showSettings.toggle()
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Circle())
                            }
                        }

                        // Settings Sheet Card (when gear tapped)
                        if vm.showSettings {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("SETTINGS")
                                    .font(.caption.bold())
                                    .foregroundColor(accent)

                                if vm.isPaired {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(vm.pcName.isEmpty ? "Connected PC" : vm.pcName)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.white)
                                            Text("\(vm.pcHost):\(vm.pcPort)")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        Button("Disconnect") {
                                            vm.disconnect()
                                        }
                                        .font(.caption.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(accent)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                    }
                                    .padding(10)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                DisclosureGroup("Manual / Tailscale IP", isExpanded: $vm.showManualEntry) {
                                    VStack(spacing: 8) {
                                        TextField("PC IP (Wi-Fi or Tailscale 100.x.x.x)", text: $vm.pcHost)
                                            .textFieldStyle(.roundedBorder)
                                            .autocapitalization(.none)
                                            .keyboardType(.URL)
                                        TextField("Port (58742)", text: $vm.pcPort)
                                            .textFieldStyle(.roundedBorder)
                                            .keyboardType(.numberPad)
                                        TextField("Pair Key", text: $vm.pairKey)
                                            .textFieldStyle(.roundedBorder)
                                            .autocapitalization(.allCharacters)
                                        Button("Save & Connect") {
                                            vm.saveManualPairing()
                                        }
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(accent)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .padding(.top, 8)
                                }
                                .tint(accent)
                                .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // Nearby Devices Discovery Card (shown when NOT paired)
                        if !vm.isPaired {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("NEARBY DEVICES")
                                        .font(.caption.bold())
                                        .foregroundColor(accent)
                                    Spacer()
                                    if vm.isScanning {
                                        ProgressView().tint(accent)
                                    } else {
                                        Button("Scan Again") { vm.scanNearby() }
                                            .font(.caption.bold())
                                            .foregroundColor(accent)
                                    }
                                }

                                if vm.discoveredDevices.isEmpty {
                                    Text(vm.isScanning ? "Looking for ror on nearby PCs..." : "No nearby PCs found on this Wi-Fi. Open ror on your PC or tap Settings for manual/Tailscale IP.")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(vm.discoveredDevices) { dev in
                                        HStack(spacing: 12) {
                                            Image(systemName: "desktopcomputer")
                                                .font(.title2)
                                                .foregroundColor(accent)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(dev.deviceName)
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(.white)
                                                Text(dev.host)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                            Button("Connect") {
                                                vm.connectToDevice(dev)
                                            }
                                            .font(.caption.bold())
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(accent)
                                            .foregroundColor(.white)
                                            .clipShape(Capsule())
                                        }
                                        .padding(12)
                                        .background(Color.black.opacity(0.45))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // Send & Receive Cards (when paired)
                        if vm.isPaired {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SEND TO \(vm.pcName.isEmpty ? "PC" : vm.pcName.uppercased())")
                                    .font(.caption.bold())
                                    .foregroundColor(accent)

                                HStack(spacing: 10) {
                                    PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos])) {
                                        Label("Photo / Video", systemImage: "photo.on.rectangle")
                                            .font(.subheadline.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(accent)
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }

                                    Button {
                                        showFileImporter = true
                                    } label: {
                                        Label("File", systemImage: "doc")
                                            .font(.subheadline.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.white.opacity(0.1))
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }

                                HStack {
                                    TextField("Send text or link to PC...", text: $vm.textToSend)
                                        .padding(10)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button {
                                        vm.sendText()
                                    } label: {
                                        Image(systemName: "paperplane.fill")
                                            .padding(10)
                                            .background(accent)
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            VStack(alignment: .leading, spacing: 10) {
                                Text("RECEIVED FROM PC")
                                    .font(.caption.bold())
                                    .foregroundColor(accent)

                                if vm.receivedItems.isEmpty {
                                    Text("No items received yet. Anything sent from your PC will appear here automatically.")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 12)
                                } else {
                                    ForEach(vm.receivedItems) { item in
                                        HStack {
                                            Image(systemName: item.type == "text" ? "text.alignleft" : (item.type == "video" ? "video.fill" : (item.type == "image" ? "photo.fill" : "doc.fill")))
                                                .foregroundColor(accent)
                                                .frame(width: 30)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title)
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                Text(item.detail)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(2)
                                            }
                                            Spacer()
                                            if item.type == "text" {
                                                Button("Copy") {
                                                    UIPasteboard.general.string = item.detail
                                                    vm.statusText = "Copied to clipboard"
                                                }
                                                .font(.caption.bold())
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.white.opacity(0.1))
                                                .foregroundColor(.white)
                                                .clipShape(Capsule())
                                            }
                                        }
                                        .padding(10)
                                        .background(Color.black.opacity(0.35))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding()
                }
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let ext = newItem.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ror_\(Int(Date().timeIntervalSince1970)).\(ext)")
                    try? data.write(to: tmp)
                    vm.sendLocalFile(tmp)
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { res in
            if case .success(let url) = res {
                let accessed = url.startAccessingSecurityScopedResource()
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try? FileManager.default.copyItem(at: url, to: tmp)
                if accessed { url.stopAccessingSecurityScopedResource() }
                vm.sendLocalFile(tmp)
            }
        }
    }
}
