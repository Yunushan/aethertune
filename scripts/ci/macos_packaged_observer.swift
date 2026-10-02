// External observer only: never linked into or used to re-sign the product.
import AppKit
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import Security

let bundleID = "dev.aethertune.aethertune"
let fileManager = FileManager.default
let env = ProcessInfo.processInfo.environment

struct ObservationError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ObservationError(message) }
}

func write(_ value: [String: Any], to path: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: path, options: .atomic)
}

func sha256(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

func wait(_ seconds: Double, until predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return predicate()
}

func keychainMetadata() throws -> [String: Any] {
    var stores: [[String: Any]] = []
    var appCount = 0
    for protection in [false, true] {
        // The default service is fixed by flutter_secure_storage11.2.0.
        // Return attributes only. Fail on access/entitlement errors and never
        // request authentication UI, secret values, or keychain mutations.
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "flutter_secure_storage_service",
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnData: false,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
            kSecAttrSynchronizable: false
        ]
        if protection { query[kSecUseDataProtectionKeychain] = true }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        try require(status == errSecSuccess || status == errSecItemNotFound,
                    "Keychain metadata inventory inaccessible (\(status)); absence is not established.")
        let rows = result as? [[String: Any]] ?? []
        if status == errSecSuccess {
            try require(result != nil && result is [[String: Any]], "Unexpected keychain metadata result type.")
        }
        let count = rows.filter {
            guard let account = $0[kSecAttrAccount as String] as? String else { return false }
            return account == "aethertune.library_sync.token.v1" || account.hasPrefix("aethertune.provider.secret.v1.")
        }.count
        appCount += count
        stores.append(["dataProtection": protection, "status": Int(status),
                       "visibleServiceItemCount": rows.count, "visibleAppItemCount": count])
    }
    return ["stores": stores, "appItemCount": appCount,
            "scope": "Observer-visible metadata only; no secret values, credential writes, or global access-group claim."]
}

func snapshot() throws -> [String: Any] {
    guard let passwd = getpwuid(getuid()), let directory = passwd.pointee.pw_dir else {
        throw ObservationError("Actual passwd home unavailable.")
    }
    let keychain = try keychainMetadata()
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    var sessionMetadata: [String: Any] = [:]
    for key in ["kCGSSessionUserIDKey", "kCGSSessionUserNameKey", "kCGSSessionOnConsoleKey", "kCGSSessionLoginDoneKey"] {
        if let value = session[key] { sessionMetadata[key] = value }
    }
    return ["foundationHome": NSHomeDirectory(), "passwdHome": String(cString: directory),
            "username": NSUserName(), "uid": Int(getuid()),
            "graphicsSessionAvailable": !session.isEmpty, "graphicsSession": sessionMetadata,
            "screenCaptureAllowed": CGPreflightScreenCaptureAccess(),
            "runningAppCount": NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count,
            "keychainAppItemCount": keychain["appItemCount"]!, "keychain": keychain]
}

func errorChain(_ error: Error) -> [[String: Any]] {
    var result: [[String: Any]] = []
    var current: NSError? = error as NSError
    while let value = current, result.count < 8 {
        var row: [String: Any] = ["domain": value.domain, "code": value.code,
                                  "description": String(value.localizedDescription.prefix(4096))]
        if let reason = value.localizedFailureReason { row["failureReason"] = String(reason.prefix(4096)) }
        result.append(row)
        current = value.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return result
}

func ownedBundle(_ app: URL) throws -> URL {
    let bundle = app.standardizedFileURL
    let stage = bundle.deletingLastPathComponent()
    guard let temp = env["RUNNER_TEMP"] else { throw ObservationError("RUNNER_TEMP unavailable.") }
    let prefix = URL(fileURLWithPath: temp).resolvingSymlinksInPath().path + "/"
    try require(bundle.lastPathComponent == "aethertune.app"
                && stage.path.hasPrefix(prefix)
                && stage.lastPathComponent.range(of: "^aethertune-macos-ordinary-[0-9a-f]{32}$", options: .regularExpression) != nil
                && bundle.resolvingSymlinksInPath().path == bundle.path,
                "Bundle is outside the exact newly owned stage.")
    let marker = try Data(contentsOf: stage.appendingPathComponent(".owned"))
    try require(marker == Data("aethertune-macos-packaged-v1\n".utf8), "Owned stage marker mismatch.")
    return bundle
}

func identity(_ app: NSRunningApplication, bundle: URL, expectedHash: String) throws -> [String: Any] {
    guard let actualBundle = app.bundleURL?.standardizedFileURL,
          let executable = app.executableURL?.standardizedFileURL, let date = app.launchDate else {
        throw ObservationError("Native app identity unavailable.")
    }
    let expectedExecutable = bundle.appendingPathComponent("Contents/MacOS/aethertune")
    let executableHash = try sha256(executable)
    var process = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
    try require(proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &process, size) == size
                && process.pbi_uid == getuid() && process.pbi_start_tvsec > 0,
                "Owned application UID/start-time metadata unavailable or mismatched.")
    try require(app.bundleIdentifier == bundleID && actualBundle == bundle
                && executable == expectedExecutable && app.processIdentifier > 0
                && executableHash == expectedHash, "Native PID/path/bundle/hash mismatch.")
    return ["pid": Int(app.processIdentifier), "bundleURL": bundle.path,
            "executableURL": executable.path, "launchDate": date.timeIntervalSince1970,
            "executableSha256": expectedHash, "uid": Int(process.pbi_uid),
            "startSeconds": process.pbi_start_tvsec, "startMicroseconds": process.pbi_start_tvusec]
}

// XNU permits NOTE_EXITSTATUS for a target the observer may signal. Actual
// registration and event flags are checked: no debugger, signal, or permission
// grant is used to obtain the status. Unsupported access fails the acceptance.
final class ExitWatch {
    let descriptor: Int32
    let pid: pid_t
    init(_ pid: pid_t) throws {
        self.pid = pid
        descriptor = kqueue()
        try require(descriptor >= 0, "Owned exit kqueue creation failed (\(errno)).")
        var change = kevent64_s()
        change.ident = UInt64(pid)
        change.filter = Int16(EVFILT_PROC)
        change.flags = UInt16(EV_ADD | EV_ONESHOT | EV_RECEIPT)
        change.fflags = UInt32(NOTE_EXIT) | UInt32(NOTE_EXITSTATUS)
        var receipt = kevent64_s()
        var immediate = timespec(tv_sec: 0, tv_nsec: 0)
        let count = kevent64(descriptor, &change, 1, &receipt, 1, 0, &immediate)
        if count != 1 || receipt.flags & UInt16(EV_ERROR) == 0 || receipt.data != 0 {
            let code = count < 0 ? Int64(errno) : receipt.data
            close(descriptor)
            throw ObservationError("Exact owned PID exit-status registration failed (\(code)).")
        }
    }
    deinit { close(descriptor) }
    func read() throws -> [String: Any] {
        var event = kevent64_s()
        var deadline = timespec(tv_sec: 5, tv_nsec: 0)
        let count = kevent64(descriptor, nil, 0, &event, 1, 0, &deadline)
        let expectedFlags = UInt32(NOTE_EXIT) | UInt32(NOTE_EXITSTATUS)
        try require(count == 1 && event.ident == UInt64(pid)
                    && event.filter == Int16(EVFILT_PROC)
                    && event.flags & UInt16(EV_ERROR) == 0
                    && event.fflags & expectedFlags == expectedFlags,
                    "Missing exact owned PID NOTE_EXIT/NOTE_EXITSTATUS event (\(errno)).")
        return ["pid": Int(pid), "rawWaitStatus": event.data,
                "exitCode": (event.data >> 8) & 0xff, "signal": event.data & 0x7f,
                "flags": event.flags, "filterFlags": event.fflags]
    }
}

func matches(_ app: NSRunningApplication, receipt: [String: Any]) throws -> Bool {
    guard let path = receipt["bundleURL"] as? String, let hash = receipt["executableSha256"] as? String,
          let launchDate = receipt["launchDate"] as? Double, let pid = receipt["pid"] as? Int else {
        throw ObservationError("Incomplete owned app receipt.")
    }
    let bundle = try ownedBundle(URL(fileURLWithPath: path))
    let current = try identity(app, bundle: bundle, expectedHash: hash)
    return current["pid"] as? Int == pid && current["launchDate"] as? Double == launchDate
        && (current["uid"] as? NSNumber) == (receipt["uid"] as? NSNumber)
        && (current["startSeconds"] as? NSNumber) == (receipt["startSeconds"] as? NSNumber)
        && (current["startMicroseconds"] as? NSNumber) == (receipt["startMicroseconds"] as? NSNumber)
}

func stopOwned(_ receipt: [String: Any], permitForcedCleanup: Bool) throws -> [String: Any] {
    guard let receiptPID = receipt["pid"] as? Int, let pid = pid_t(exactly: receiptPID), pid > 0 else {
        throw ObservationError("Missing or out-of-range owned PID.")
    }
    guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
        return ["ownedProcessAbsent": true, "alreadyAbsent": true]
    }
    try require(try matches(app, receipt: receipt), "PID/path/launch-date identity changed; refusing termination.")
    let requested = app.terminate()
    let normal = requested && wait(10) { app.isTerminated }
    if !normal && permitForcedCleanup {
        try require(try matches(app, receipt: receipt), "Owned identity changed before forced cleanup.")
        _ = app.forceTerminate()
    }
    let absent = wait(5) { app.isTerminated }
    try require(absent, "Exact owned application did not terminate.")
    return ["ownedProcessAbsent": absent, "normalQuit": normal, "forcedCleanupUsed": !normal]
}

func mainWindow(_ pid: pid_t) -> [String: Any]? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { return nil }
    return windows.filter { window in
        guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
              (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber else { return false }
        return width.doubleValue >= 100 && height.doubleValue >= 100
    }.max { left, right in
        func area(_ window: [String: Any]) -> Double {
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber else { return 0 }
            return width.doubleValue * height.doubleValue
        }
        return area(left) < area(right)
    }
}

func runApp(_ bundle: URL, evidence: URL, expectedHash: String) throws {
    let bundle = try ownedBundle(bundle)
    try require(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
                "Preexisting ordinary app prevents isolated ownership.")
    try require(CGPreflightScreenCaptureAccess(), "Existing screen capture permission unavailable; no grant requested.")
    var result: [String: Any] = ["status": "starting", "normalQuit": false, "ownedProcessAbsent": false]
    var receipt: [String: Any]?
    var launched: NSRunningApplication?
    do {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.activates = true
        var completed = false
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { application, error in
            launched = application
            launchError = error
            completed = true
        }
        try require(wait(45) { completed }, "Native ordinary app launch timed out.")
        if let error = launchError { throw error }
        guard let application = launched else { throw ObservationError("No native application launch handle.") }
        receipt = try identity(application, bundle: bundle, expectedHash: expectedHash)
        try write(receipt!, to: evidence.appendingPathComponent("launch-identity.json"))
        result["identity"] = receipt!
        let exitWatch = try ExitWatch(application.processIdentifier)
        try require(try matches(application, receipt: receipt!), "Owned identity changed during exit watcher registration.")
        result["exitStatusWatchAttached"] = true
        let cpu = application.executableArchitecture
        result["executedArchitecture"] = cpu == CPU_TYPE_ARM64 ? "arm64" : cpu == CPU_TYPE_X86_64 ? "x86_64" : "unknown"
        try require(cpu == CPU_TYPE_ARM64 || cpu == CPU_TYPE_X86_64, "Unexpected running executable architecture.")
        var window: [String: Any]?
        try require(wait(45) {
            if application.isTerminated { return true }
            window = mainWindow(application.processIdentifier)
            return application.isFinishedLaunching && window != nil
        } && !application.isTerminated && window != nil, "Ordinary app has no live owned window.")
        let visibleUntil = Date().addingTimeInterval(15)
        while Date() < visibleUntil {
            try require(!application.isTerminated && mainWindow(application.processIdentifier) != nil,
                        "Ordinary app/window disappeared during15-second observation.")
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        window = mainWindow(application.processIdentifier)
        guard let windowID = (window?[kCGWindowNumber as String] as? NSNumber)?.intValue else {
            throw ObservationError("Owned window ID unavailable.")
        }
        result["windowID"] = windowID
        result["windowBounds"] = window?[kCGWindowBounds as String]
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(windowID), evidence.appendingPathComponent("ordinary-window.png").path]
        try capture.run()
        if !wait(10, until: { !capture.isRunning }) {
            capture.terminate()
            if !wait(2, until: { !capture.isRunning }) { _ = kill(capture.processIdentifier, SIGKILL) }
            let absent = wait(3, until: { !capture.isRunning })
            result["captureHelperAbsentAfterTimeout"] = absent
            throw ObservationError("Owned capture helper timed out; absent=\(absent).")
        }
        try require(capture.terminationStatus == 0, "Owned window capture failed.")
        result["capturePid"] = Int(capture.processIdentifier)
        let quit = try stopOwned(receipt!, permitForcedCleanup: true)
        result.merge(quit) { _, new in new }
        try require(quit["normalQuit"] as? Bool == true, "App required forced cleanup instead of normal quit.")
        let exitReceipt = try exitWatch.read()
        result["exit"] = exitReceipt
        try require(exitReceipt["rawWaitStatus"] as? Int64 == 0,
                    "Owned ordinary app quit with nonzero native wait status.")
        result["status"] = "passed"
    } catch {
        result["status"] = "failed"
        result["error"] = String(describing: error)
        result["errorChain"] = errorChain(error)
        if let receipt = receipt {
            do { result["failureCleanup"] = try stopOwned(receipt, permitForcedCleanup: true) }
            catch { result["cleanupError"] = String(describing: error) }
        }
        try write(result, to: evidence.appendingPathComponent("native-result.json"))
        throw error
    }
    try write(result, to: evidence.appendingPathComponent("native-result.json"))
}

do {
    try require(env["GITHUB_ACTIONS"] == "true" && env["RUNNER_ENVIRONMENT"] == "github-hosted"
                && env["RUNNER_OS"] == "macOS" && env["GITHUB_REPOSITORY"] == "Yunushan/aethertune"
                && ["workflow_dispatch", "pull_request"].contains(env["GITHUB_EVENT_NAME"] ?? ""),
                "Hosted scoped runner guard failed.")
    let args = CommandLine.arguments
    if args.count == 2 && args[1] == "snapshot" {
        let data = try JSONSerialization.data(withJSONObject: snapshot(), options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else if args.count == 5 && args[1] == "run" {
        try runApp(URL(fileURLWithPath: args[2]), evidence: URL(fileURLWithPath: args[3]), expectedHash: args[4])
    } else if args.count == 3 && args[1] == "cleanup" {
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        guard let receipt = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ObservationError("Invalid cleanup receipt.")
        }
        let value = try stopOwned(receipt, permitForcedCleanup: true)
        print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self))
    } else { throw ObservationError("Invalid observer arguments.") }
} catch {
    FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
    exit(1)
}
