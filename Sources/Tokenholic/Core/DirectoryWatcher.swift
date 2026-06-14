import Foundation
import CoreServices

/// Watches directories for file changes via FSEvents and fires `onChange`
/// (already coalesced by `latency`) on a background dispatch queue.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "ai.conol.Tokenholic.fsevents")
    private let onChange: () -> Void

    init?(paths: [String], latency: TimeInterval = 3.0, onChange: @escaping () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit { stop() }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // Non-capturing C callback; recovers `self` from the context info pointer.
    private static let eventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
    }
}
