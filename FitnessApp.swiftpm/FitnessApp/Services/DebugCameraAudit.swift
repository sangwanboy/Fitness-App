#if DEBUG
import Foundation

/// On-device diagnostic tripwire for the food camera's start/stop lifecycle.
/// Appends one JSON line per event to Documents/camera_audit.jsonl, written
/// SYNCHRONOUSLY (FileHandle append + fsync) so a hung `startRunning` still
/// leaves its `invoke` line behind — the whole point is surviving a wedge,
/// not just a clean shutdown. DEBUG-only, read-only conceptually (it never
/// influences FoodCameraModel's behavior), pull with `devicectl device copy`
/// and inspect without a debugger. Modeled on DebugNotificationAudit.
enum DebugCameraAudit {
    private static let queue = DispatchQueue(label: "fitnessapp.debug.cameraaudit")
    private static var handle: FileHandle?

    static func log(_ event: String, _ info: [String: Any] = [:]) {
        queue.sync {
            var line: [String: Any] = [
                "ts": Self.iso8601.string(from: Date()),
                "event": event,
            ]
            if !info.isEmpty { line["info"] = info }

            guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
                  var text = String(data: data, encoding: .utf8) else { return }
            text += "\n"
            guard let payload = text.data(using: .utf8) else { return }

            if handle == nil { handle = openHandle() }
            guard let handle else { return }
            handle.seekToEndOfFile()
            handle.write(payload)
            // fsync so a wedged startRunning still leaves this line on disk
            // even if the app is later force-killed rather than crashing.
            fsync(handle.fileDescriptor)
        }
    }

    private static let iso8601 = ISO8601DateFormatter()

    private static func openHandle() -> FileHandle? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent("camera_audit.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return try? FileHandle(forWritingTo: url)
    }
}
#endif
