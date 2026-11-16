import Foundation
import CryptoKit
import Security

/// Telefonda şifrəli saxlanan fayllar (internetsiz nüsxə, kitab tarixləri, cədvəl şəkli).
/// Açar Keychain-də saxlanılır (yalnız bu iPhone, kilid açıldıqdan sonra), fayllar AES-GCM ilə şifrələnir.
enum SecureStore {
    private static let service = "com.nexora.beueduaz.cachekey"
    private static let lock = NSLock()

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("secure", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            var v = URLResourceValues(); v.isExcludedFromBackup = true
            var u = d; try? u.setResourceValues(v)
        }
        return d
    }

    private static func url(_ name: String) -> URL { dir.appendingPathComponent(name + ".bin") }

    /// Açar: yoxdursa yaradılır.
    private static func key() -> SymmetricKey? {
        lock.lock(); defer { lock.unlock() }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "aes",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, d.count == 32 {
            return SymmetricKey(data: d)
        }
        let k = SymmetricKey(size: .bits256)
        let data = k.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "aes",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        return k
    }

    static func write(_ data: Data, _ name: String) {
        guard let k = key(), let box = try? AES.GCM.seal(data, using: k), let sealed = box.combined else { return }
        try? sealed.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read(_ name: String) -> Data? {
        guard let raw = try? Data(contentsOf: url(name)), let k = key(),
              let box = try? AES.GCM.SealedBox(combined: raw) else { return nil }
        return try? AES.GCM.open(box, using: k)
    }

    static func remove(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }

    static func writeJSON<T: Encodable>(_ value: T, _ name: String) {
        if let d = try? JSONEncoder().encode(value) { write(d, name) }
    }

    static func readJSON<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        read(name).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Çıxışda: bütün şifrəli fayllar və açar silinir.
    static func wipe() {
        try? FileManager.default.removeItem(at: dir)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
    }
}
