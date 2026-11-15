import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

        let host = UIHostingController(rootView: ShareRootView(
            extensionContext: extensionContext,
            onDone: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
}

struct ShareRootView: View {
    let extensionContext: NSExtensionContext?
    let onDone: () -> Void

    @State private var stateText = "Sending to PC..."
    @State private var isDone = false
    @State private var isError = false
    @State private var needsSetup = (RorConfigStore.baseURLString == nil)
    @State private var pcHost = RorConfigStore.pcHost
    @State private var pairKey = RorConfigStore.pairKey

    let accent = Color(red: 1.0, green: 0.165, blue: 0.23)

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("R")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(accent)
                    .frame(width: 56, height: 56)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if needsSetup {
                    Text("Pair with ror PC")
                        .font(.headline)
                        .foregroundColor(.white)
                    TextField("PC IP (e.g. 192.168.1.5 or 100.x.x.x)", text: $pcHost)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                    TextField("Pair Key", text: $pairKey)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.allCharacters)
                    Button("Save & Send") {
                        RorConfigStore.pcHost = pcHost
                        RorConfigStore.pairKey = pairKey
                        needsSetup = false
                        startSending()
                    }
                    .fontWeight(.bold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(accent)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                } else {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 46))
                            .foregroundColor(.green)
                    } else if isError {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 46))
                            .foregroundColor(accent)
                    } else {
                        ProgressView()
                            .tint(accent)
                            .scaleEffect(1.3)
                    }
                    Text(stateText)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if isError {
                        Button("Close") { onDone() }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if !needsSetup { startSending() }
        }
    }

    private func startSending() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finishError("Nothing to send")
            return
        }
        var providers: [NSItemProvider] = []
        for item in items {
            if let attachments = item.attachments {
                providers.append(contentsOf: attachments)
            }
        }
        guard !providers.isEmpty else {
            finishError("No supported items found")
            return
        }
        stateText = "Sending \(providers.count) item(s) to PC..."
        sendNext(providers, index: 0)
    }

    private func sendNext(_ providers: [NSItemProvider], index: Int) {
        if index >= providers.count {
            DispatchQueue.main.async {
                isDone = true
                stateText = "Sent to PC!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    onDone()
                }
            }
            return
        }
        let provider = providers[index]
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            loadFile(provider, typeId: UTType.movie.identifier, defaultExt: "mp4") { url in
                self.uploadTempFile(url) { self.sendNext(providers, index: index + 1) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            loadFile(provider, typeId: UTType.image.identifier, defaultExt: "jpg") { url in
                self.uploadTempFile(url) { self.sendNext(providers, index: index + 1) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            loadFile(provider, typeId: UTType.fileURL.identifier, defaultExt: "dat") { url in
                self.uploadTempFile(url) { self.sendNext(providers, index: index + 1) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    RorNetwork.uploadText(url.absoluteString) { res in
                        self.handleResult(res) { self.sendNext(providers, index: index + 1) }
                    }
                } else {
                    self.finishError("Could not read URL")
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    RorNetwork.uploadText(text) { res in
                        self.handleResult(res) { self.sendNext(providers, index: index + 1) }
                    }
                } else {
                    self.finishError("Could not read text")
                }
            }
        } else {
            loadFile(provider, typeId: UTType.item.identifier, defaultExt: "bin") { url in
                self.uploadTempFile(url) { self.sendNext(providers, index: index + 1) }
            }
        }
    }

    private func loadFile(_ provider: NSItemProvider, typeId: String, defaultExt: String, completion: @escaping (URL) -> Void) {
        provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, err in
            if let url = url {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try? FileManager.default.copyItem(at: url, to: tmp)
                completion(tmp)
            } else {
                provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
                    if let img = item as? UIImage, let data = img.jpegData(compressionQuality: 0.95) {
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("IMG_\(Int(Date().timeIntervalSince1970)).jpg")
                        try? data.write(to: tmp)
                        completion(tmp)
                    } else if let data = item as? Data {
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("file_\(Int(Date().timeIntervalSince1970)).\(defaultExt)")
                        try? data.write(to: tmp)
                        completion(tmp)
                    } else {
                        self.finishError(err?.localizedDescription ?? "Failed to read item")
                    }
                }
            }
        }
    }

    private func uploadTempFile(_ url: URL, next: @escaping () -> Void) {
        RorNetwork.uploadFile(fileURL: url, filename: url.lastPathComponent) { res in
            self.handleResult(res, next: next)
        }
    }

    private func handleResult(_ res: Result<Void, Error>, next: @escaping () -> Void) {
        switch res {
        case .success:
            next()
        case .failure(let err):
            finishError(err.localizedDescription)
        }
    }

    private func finishError(_ msg: String) {
        DispatchQueue.main.async {
            isError = true
            stateText = msg
        }
    }
}
