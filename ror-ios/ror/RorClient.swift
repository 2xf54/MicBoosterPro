import Darwin
import Foundation
import Intents
import Photos
import UIKit

struct RorQueueItem: Codable, Identifiable {
    let id: String
    let type: String
    let filename: String
    let size: Int
    let text: String?
    let created_at: Int?
}

struct RorQueueResponse: Codable {
    let items: [RorQueueItem]
}

struct RorReceivedEntry: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let detail: String
    let localPath: String?
    let date: Date
}

struct RorChatMessage: Codable, Identifiable {
    let id: String
    let isMe: Bool
    let text: String
    let date: Date
    var localPath: String? = nil
    var mediaType: String? = nil // "image", "video", "file", nil
}

enum RorSiriShareDonor {
    static func donateWindowsPC() {
        let handle = INPersonHandle(value: "windows-pc@ror.local", type: .unknown)
        let recipient = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: "Windows PC",
            image: nil,
            contactIdentifier: nil,
            customIdentifier: "ror-windows-pc"
        )
        let intent = INSendMessageIntent(
            recipients: [recipient],
            outgoingMessageType: .outgoingMessageText,
            content: nil,
            speakableGroupName: INSpeakableString(spokenPhrase: "Windows PC"),
            conversationIdentifier: "ror-windows-pc",
            serviceName: "ror",
            sender: nil,
            attachments: nil
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        interaction.donate { _ in }
    }
}

struct RorDiscoveredDevice: Identifiable, Hashable {
    var id: String { "\(host):\(port)" }
    let host: String
    let port: Int
    let deviceName: String
    let pairKey: String
}

final class RorConfigStore {
    private static let hostKey = "ror_pc_host"
    private static let portKey = "ror_pc_port"
    private static let pairKeyKey = "ror_pair_key"
    private static let nameKey = "ror_pc_name"

    static var pcHost: String {
        get { UserDefaults.standard.string(forKey: hostKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: hostKey) }
    }

    static var pcPort: String {
        get { UserDefaults.standard.string(forKey: portKey) ?? "58742" }
        set { UserDefaults.standard.set(newValue, forKey: portKey) }
    }

    static var pairKey: String {
        get { UserDefaults.standard.string(forKey: pairKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: pairKeyKey) }
    }

    static var pcName: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    static var isPaired: Bool {
        !pcHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !pairKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func disconnect() {
        UserDefaults.standard.removeObject(forKey: hostKey)
        UserDefaults.standard.removeObject(forKey: portKey)
        UserDefaults.standard.removeObject(forKey: pairKeyKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    static var baseURLString: String? {
        let host = pcHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = pcPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            return host
        }
        return "http://\(host):\(port.isEmpty ? "58742" : port)"
    }
}

final class RorDiscovery {
    static func scan(timeoutSeconds: Double = 2.0, completion: @escaping ([RorDiscoveredDevice]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [String: RorDiscoveredDevice] = [:]
            let sock = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            if sock < 0 {
                DispatchQueue.main.async { completion([]) }
                return
            }
            defer { Darwin.close(sock) }

            var yes: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

            var tv = timeval(tv_sec: 0, tv_usec: 400_000)
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var targets: [sockaddr_in] = []
            var bcast = sockaddr_in()
            bcast.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            bcast.sin_family = sa_family_t(AF_INET)
            bcast.sin_port = UInt16(58743).bigEndian
            bcast.sin_addr.s_addr = inet_addr("255.255.255.255")
            targets.append(bcast)

            // Also send to active Wi-Fi interface broadcast address
            var ifaddr: UnsafeMutablePointer<ifaddrs>?
            if getifaddrs(&ifaddr) == 0, let first = ifaddr {
                var ptr: UnsafeMutablePointer<ifaddrs>? = first
                while let cur = ptr {
                    if cur.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET),
                       let dst = cur.pointee.ifa_dstaddr,
                       dst.pointee.sa_family == UInt8(AF_INET) {
                        var sin = dst.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                        sin.sin_port = UInt16(58743).bigEndian
                        targets.append(sin)
                    }
                    ptr = cur.pointee.ifa_next
                }
                freeifaddrs(first)
            }

            let msg = Array("ROR_DISCOVER".utf8)
            for var addr in targets {
                _ = msg.withUnsafeBytes { buf in
                    withUnsafePointer(to: &addr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            Darwin.sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            var recvBuf = [UInt8](repeating: 0, count: 2048)
            while Date() < deadline {
                var srcAddr = sockaddr_in()
                var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &srcAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        Darwin.recvfrom(sock, &recvBuf, recvBuf.count, 0, sa, &srcLen)
                    }
                }
                if n > 0 {
                    let data = Data(recvBuf.prefix(n))
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       (obj["app"] as? String) == "ror",
                       let devName = obj["device"] as? String,
                       let port = obj["port"] as? Int,
                       let key = obj["pair_key"] as? String {
                        var ipC = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        var inAddr = srcAddr.sin_addr
                        inet_ntop(AF_INET, &inAddr, &ipC, socklen_t(INET_ADDRSTRLEN))
                        let ip = String(cString: ipC)
                        let dev = RorDiscoveredDevice(host: ip, port: port, deviceName: devName, pairKey: key)
                        found[dev.id] = dev
                    }
                }
            }

            let list = found.values.sorted { $0.deviceName < $1.deviceName }
            DispatchQueue.main.async {
                completion(list)
            }
        }
    }
}

final class RorNetwork {
    static func ping(baseURL: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/ping") else {
            completion(.failure(NSError(domain: "ror", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid PC address"])))
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err {
                completion(.failure(err))
                return
            }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let device = obj["device"] as? String else {
                completion(.failure(NSError(domain: "ror", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unexpected response"])))
                return
            }
            completion(.success(device))
        }.resume()
    }

    static func uploadFile(fileURL: URL, filename: String, batchId: String? = nil, batchCount: Int = 1, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let base = RorConfigStore.baseURLString,
              let url = URL(string: "\(base)/upload") else {
            completion(.failure(NSError(domain: "ror", code: -1, userInfo: [NSLocalizedDescriptionKey: "PC not paired"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue(RorConfigStore.pairKey, forHTTPHeaderField: "X-Pair-Key")
        req.setValue("file", forHTTPHeaderField: "X-Type")
        req.setValue(UIDevice.current.name, forHTTPHeaderField: "X-Sender")
        let encodedName = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
        req.setValue(encodedName, forHTTPHeaderField: "X-Filename")
        if let batchId = batchId, batchCount > 1 {
            req.setValue(batchId, forHTTPHeaderField: "X-Batch-Id")
            req.setValue(String(batchCount), forHTTPHeaderField: "X-Batch-Count")
        }

        URLSession.shared.uploadTask(with: req, fromFile: fileURL) { _, resp, err in
            if let err = err {
                completion(.failure(err))
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "ror", code: code, userInfo: [NSLocalizedDescriptionKey: "Server error HTTP \(code)"])))
            }
        }.resume()
    }

    static func uploadText(_ text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let base = RorConfigStore.baseURLString,
              let url = URL(string: "\(base)/upload") else {
            completion(.failure(NSError(domain: "ror", code: -1, userInfo: [NSLocalizedDescriptionKey: "PC not paired"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue(RorConfigStore.pairKey, forHTTPHeaderField: "X-Pair-Key")
        req.setValue("text", forHTTPHeaderField: "X-Type")
        req.setValue(UIDevice.current.name, forHTTPHeaderField: "X-Sender")
        req.httpBody = text.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err {
                completion(.failure(err))
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "ror", code: code, userInfo: [NSLocalizedDescriptionKey: "Server error HTTP \(code)"])))
            }
        }.resume()
    }
}
