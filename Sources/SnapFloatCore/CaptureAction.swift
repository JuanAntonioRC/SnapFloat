import Foundation

/// What happens immediately after a screenshot is captured.
/// Mirrors SnapFloat/SettingsManager.swift's `CaptureAction` on macOS —
/// kept as a separate copy so the mac target doesn't need to depend on
/// this package. See the plan's "optional follow-up" note if these are
/// ever unified.
public enum CaptureAction: Int, Sendable {
    case copyToClipboard     = 0
    case doNothing           = 1
    case saveToFolder        = 2
    case copyAndSaveToFolder = 3
}
