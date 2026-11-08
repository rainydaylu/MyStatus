import Foundation

public enum Format {
    public static func speed(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1_000_000 { return "\(Int((value / 1000).rounded())) KB/s" }
        if value < 10_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        if value < 1_000_000_000 { return "\(Int((value / 1_000_000).rounded())) MB/s" }
        return String(format: "%.1f GB/s", value / 1_000_000_000)
    }

    /// Storage in decimal units as Finder shows it; memory in binary units, so
    /// that a 16 GB Mac reads as 16 GB.
    public static func bytes(_ value: UInt64, binary: Bool = false) -> String {
        let base = binary ? 1024.0 : 1000.0
        var amount = Double(value)
        var unit = "B"
        for next in ["KB", "MB", "GB", "TB"] where amount >= base {
            amount /= base
            unit = next
        }
        if unit == "B" { return "\(value) B" }
        return amount >= 100 || unit == "KB" ? "\(Int(amount.rounded())) \(unit)" : String(format: "%.1f %@", amount, unit)
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds)) / 60
        let days = total / 1440
        let hours = total % 1440 / 60
        let minutes = total % 60
        if days > 0 { return DeckLF("%ld天 %ld小时", "%ldd %ldh", days, hours) }
        if hours > 0 { return DeckLF("%ld小时%ld分钟", "%ldh %ldmin", hours, minutes) }
        return DeckLF("%ld分钟", "%ld min", minutes)
    }

    public static func gigahertz(_ megahertz: Double?) -> String {
        guard let megahertz else { return "--" }
        return String(format: "%.1f GHz", megahertz / 1000)
    }

    public static func degrees(_ celsius: Double?) -> String {
        guard let celsius else { return "--" }
        return "\(Int(celsius.rounded()))°"
    }

    public static func watts(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: value < 10 ? "%.1f W" : "%.0f W", value)
    }

    /// "刚刚", "5 分钟前", "昨天"... for clipboard history and the like.
    public static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return DeckL("刚刚") }
        if seconds < 3600 { return DeckLF("%ld 分钟前", "%ld min ago", Int(seconds / 60)) }
        if seconds < 86400 { return DeckLF("%ld 小时前", "%ldh ago", Int(seconds / 3600)) }
        if seconds < 172800 { return DeckL("昨天") }
        return DeckLF("%ld 天前", "%ldd ago", Int(seconds / 86400))
    }
}
