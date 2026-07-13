import CGtk4Shim

/// Hands freed heap pages back to the kernel after a window that held a
/// full-resolution screenshot buffer (CaptureOverlay, PreviewWindow,
/// AnnotationWindow) closes — glibc's malloc arenas otherwise keep that
/// memory mapped for reuse indefinitely. Complements the MALLOC_ARENA_MAX /
/// MALLOC_MMAP_THRESHOLD_ tuning in the .desktop launch environment (see
/// data/com.snapfloat.SnapFloat.desktop).
enum MemoryTrim {
    /// Debounced so back-to-back window closes (e.g. the capture overlay
    /// closing right as the preview opens) coalesce into a single trim.
    private static var pendingSourceId: CUnsignedInt = 0

    static func scheduleTrim(afterMs delay: UInt32 = 1500) {
        if pendingSourceId != 0 {
            g_source_remove(pendingSourceId)
        }
        // Priority 300 = G_PRIORITY_LOW: runs after any pending redraw or
        // D-Bus dispatch, so the trim never competes with something
        // latency-sensitive.
        pendingSourceId = g_timeout_add_full(300, delay, trimCallback, nil, nil)
    }

    private static let trimCallback: GSourceFunc = { _ in
        malloc_trim(0)
        pendingSourceId = 0
        return 0 // G_SOURCE_REMOVE
    }
}
