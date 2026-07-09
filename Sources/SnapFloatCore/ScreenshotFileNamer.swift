import Foundation

/// Generates the "SnapFloat_yyyy-MM-dd_HH-mm-ss.png" filename used when
/// saving a capture to disk, shared by every platform target.
public enum ScreenshotFileNamer {
    public static func makeFilename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "SnapFloat_\(formatter.string(from: date)).png"
    }
}
