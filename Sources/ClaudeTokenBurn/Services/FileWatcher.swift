import Foundation

// Watches a single file for modifications using kqueue/DispatchSource.
// More targeted than FSEvents for watching one file.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?
    private let url: URL
    private let debounceInterval: TimeInterval
    private let callback: () -> Void

    init(url: URL, debounce: TimeInterval = 2.0, callback: @escaping () -> Void) {
        self.url = url
        self.debounceInterval = debounce
        self.callback = callback
    }

    func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File doesn't exist yet; try again in 30s
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.start()
            }
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .attrib, .rename, .delete],
            queue: DispatchQueue.global(qos: .background)
        )

        source?.setEventHandler { [weak self] in
            self?.scheduleCallback()
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        debounceWork?.cancel()
    }

    private func scheduleCallback() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.callback() }
        }
        debounceWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    deinit { stop() }
}
