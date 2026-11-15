import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RorViewModel: ObservableObject {
    @Published var pcHost: String = RorConfigStore.pcHost
    @Published var pcPort: String = RorConfigStore.pcPort
    @Published var pairKey: String = RorConfigStore.pairKey
    @Published var statusText: String = "Ready"
    @Published var isSyncing: Bool = false
    @Published var textToSend: String = ""
    @Published var receivedItems: [RorReceivedEntry] = []
    @Published var showSettings: Bool = RorConfigStore.pcHost.isEmpty

    private let historyKey = "ror_received_history"

    init() {
        loadHistory()
        syncFromPC()
    }

    func savePairing() {
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
                    self?.statusText = "Connected to \(name)"
                    self?.showSettings = false
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
                    self?.statusText = "Text sent to PC"
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
                    self?.statusText = "Sent \(url.lastPathComponent) to PC"
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
                    self.statusText = "Synced • Up to date"
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
                            }
                            Spacer()
                            Button {
                                vm.syncFromPC()
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

                        if vm.showSettings {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("PC PAIRING")
                                    .font(.caption.bold())
                                    .foregroundColor(accent)
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
                                Button {
                                    vm.savePairing()
                                } label: {
                                    Text("Save & Connect")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(accent)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // Send to PC Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SEND TO PC")
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

                        // Received from PC List
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
