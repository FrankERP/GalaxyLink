import Foundation

enum USBHelper {
    enum USBError: Error, Equatable {
        case adbNotFound
        case noDevice
        case commandFailed(String)
    }

    static func parseDevices(_ adbDevicesOutput: String) -> [String] {
        adbDevicesOutput
            .split(separator: "\n")
            .dropFirst() // "List of devices attached"
            .compactMap { line in
                let cols = line.split(separator: "\t")
                guard cols.count == 2, cols[1] == "device" else { return nil }
                return String(cols[0])
            }
    }

    static func findADB() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            NSString(string: "~/Library/Android/sdk/platform-tools/adb").expandingTildeInPath,
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        // fall back to PATH
        if case .success(let path) = run("/usr/bin/which", ["adb"]),
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return path.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func enableUSBMode() -> Result<String, USBError> {
        guard let adb = findADB() else { return .failure(.adbNotFound) }
        guard case .success(let list) = run(adb, ["devices"]),
              let device = parseDevices(list).first else { return .failure(.noDevice) }
        for port in [Ports.http, Ports.ws] {
            if case .failure(let error) = run(adb, ["-s", device, "reverse", "tcp:\(port)", "tcp:\(port)"]) {
                return .failure(error)
            }
        }
        return .success("USB ready — open http://localhost:\(Ports.http) on the tablet")
    }

    private static func run(_ launchPath: String, _ args: [String]) -> Result<String, USBError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return process.terminationStatus == 0 ? .success(out) : .failure(.commandFailed(out))
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }
}
