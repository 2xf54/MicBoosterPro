import Foundation
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

final class RorConfigStore {
    static let appGroup = "group.com.ghazi.ror"
    private static let hostKey = "ror_pc_host"
    private static let portKey = "ror_pc_port"
    private static let pairKeyKey = "ror_pair_key"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var pcHost: String {
        get { defaults.string(forKey: hostKey) ?? UserDefaults.standard.string(forKey: hostKey) ?? "" }
        set {
            defaults.set(newValue, forKey: hostKey)
            UserDefaults.standard.set(newValue, forKey: hostKey)
        }
    }

    static var pcPort: String {
        get { defaults.string(forKey: portKey) ?? UserDefaults.standard.string(forKey: portKey) ?? "58742" }
        set {
            defaults.set(newValue, forKey: portKey)
            UserDefaults.standard.set(newValue, forKey: portKey)
        }
    }

    static var pairKey: String {
        get { defaults.string(forKey: pairKeyKey) ?? UserDefaults.standard.string(forKey: pairKeyKey) ?? "" }
        set {
            defaults.set(newValue, forKey: pairKeyKey)
            UserDefaults.standard.set(newValue, forKey: pairKeyKey)
        }
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

    static func uploadFile(fileURL: URL, filename: String, completion: @escaping (Result<Void, Error>) -> Void) {
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
