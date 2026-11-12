import Foundation

/// Trashes notes untouched for `days` unless their front matter says `keep: true`.
/// "Touched" = modified; editing or `touch` counts as use.
public enum Forget {
    public static var days: Int { Int(ProcessInfo.processInfo.environment["NOTES_FORGET_DAYS"] ?? "") ?? 21 }

    @discardableResult
    public static func run(dir: URL = Store.dir, days: Int = days, now: Date = Date(), dry: Bool = false) -> [URL] {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let stale = files.filter { url in
            guard url.pathExtension == "md",
                  let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  m < cutoff else { return false }
            return !kept(url)
        }
        if !dry { stale.forEach { try? fm.trashItem(at: $0, resultingItemURL: nil) } }
        return stale
    }

    static func kept(_ url: URL) -> Bool {
        guard let s = try? String(contentsOf: url, encoding: .utf8), s.hasPrefix("---") else { return false }
        let front = s.dropFirst(3).components(separatedBy: "\n---").first ?? ""
        return front.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "keep: true" }
    }
}
