import Foundation

struct LocalFile<Value: Codable> {
    let name: String

    func load() throws -> Value? {
        let url = try location()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    func save(_ value: Value) throws {
        let url = try location()
        let encoded = try JSONEncoder().encode(value)
        try encoded.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func location() throws -> URL {
        var dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        dir.append(path: "MorningCheck", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try dir.setResourceValues(flags)
        return dir.appending(path: name, directoryHint: .notDirectory)
    }
}

enum PeerKey {
    static let rating = "morning-rating-v1"
    static let ack = "morning-accepted-v1"
    static let appearance = "daybreak-appearance-v1"
}
