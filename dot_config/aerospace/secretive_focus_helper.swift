import Cocoa
import ApplicationServices

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32

@_silgen_name("SLSGetWindowOwner")
func SLSGetWindowOwner(_ cid: Int32, _ wid: UInt32, _ outOwnerCid: UnsafeMutablePointer<Int32>) -> Int32

@_silgen_name("SLSConnectionGetPID")
func SLSConnectionGetPID(_ cid: Int32, _ outPid: UnsafeMutablePointer<pid_t>) -> Int32

@_silgen_name("SLSRegisterNotifyProc")
func SLSRegisterNotifyProc(
    _ proc: @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void,
    _ event: UInt32,
    _ context: UnsafeMutableRawPointer?
) -> Int32

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ outWid: UnsafeMutablePointer<CGWindowID>) -> AXError

private let secretAgentBundleId = "com.maxgoedjen.Secretive.SecretAgent"
private let secretiveHostBundleId = "com.maxgoedjen.Secretive.Host"
private let localAuthBundleId = "com.apple.LocalAuthentication.UIAgent"
private let securityAgentBundleId = "com.apple.SecurityAgent"

private let watchedBundleIds: Set<String> = [
    secretAgentBundleId,
    secretiveHostBundleId,
    localAuthBundleId
]

private let nativeAuthBundleIds: Set<String> = [
    localAuthBundleId,
    securityAgentBundleId,
    "com.apple.coreservices.uiagent",
    "com.apple.UniversalAccessAuthWarn"
]

private let nativeAuthOwnerNames: Set<String> = [
    "coreautha",
    "SecurityAgent",
    "CoreServicesUIAgent",
    "UniversalAccessAuthWarn"
]

private func logMsg(_ msg: String) {
    let df = ISO8601DateFormatter()
    df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = "[\(df.string(from: Date()))] \(msg)\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

final class SecretiveFocusManager {
    static let shared = SecretiveFocusManager()

    private var pidToBundleId: [pid_t: String] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var presentedWids: Set<UInt32> = []
    private var lastOccludedRaiseTime: [UInt32: CFAbsoluteTime] = [:]
    private var deferredTargetDisplay: [pid_t: CGRect] = [:]
    private var lastActiveRegularPid: pid_t = 0
    private var lastNativeAuthSeenTime: CFAbsoluteTime = 0
    private var watchTimer: Timer?

    func start() {
        logMsg("started pid=\(ProcessInfo.processInfo.processIdentifier) axTrusted=\(AXIsProcessTrusted())")

        let ws = NSWorkspace.shared
        if let front = ws.frontmostApplication,
           let bid = front.bundleIdentifier,
           !watchedBundleIds.contains(bid),
           !nativeAuthBundleIds.contains(bid) {
            lastActiveRegularPid = front.processIdentifier
        }

        syncRunningWatchedApps()

        let nc = ws.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier,
                  watchedBundleIds.contains(bid) else { return }
            self?.registerWatchedApp(pid: app.processIdentifier, bundleId: bid, triggerPresentation: true)
        }

        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.unregisterWatchedApp(pid: app.processIdentifier)
        }

        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bid = app.bundleIdentifier ?? ""
            if nativeAuthBundleIds.contains(bid) {
                self.lastNativeAuthSeenTime = CFAbsoluteTimeGetCurrent()
                if watchedBundleIds.contains(bid) {
                    self.registerWatchedApp(pid: app.processIdentifier, bundleId: bid, triggerPresentation: false)
                    self.scheduleInitialPresentation(forPid: app.processIdentifier)
                }
            } else if !watchedBundleIds.contains(bid) {
                self.lastActiveRegularPid = app.processIdentifier
            }
        }

        registerSkyLightNotifications()
        refreshExistingWindowsAtStartup()

        // Lightweight watchdog (0.25s) ensures:
        // 1. Deferred SecretAgent batch windows (which spawn right as coreautha is cancelled during
        //    "Multiple pending requests exist, cancelling existing auth prompt") are IMMEDIATELY raised
        //    the moment coreautha finishes closing.
        // 2. Active SecretAgent batch prompt windows never stay hidden underneath full-screen/tiled apps
        //    such as Antigravity while waiting for user action (unless native macOS auth is active).
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollSecretAgentVisibility()
        }
    }

    private func syncRunningWatchedApps() {
        for (pid, _) in Array(pidToBundleId) {
            if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
                continue
            }
            unregisterWatchedApp(pid: pid)
        }

        for bid in watchedBundleIds {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bid) where !app.isTerminated {
                registerWatchedApp(pid: app.processIdentifier, bundleId: bid, triggerPresentation: false)
            }
        }
    }

    private func registerWatchedApp(pid: pid_t, bundleId: String, triggerPresentation: Bool) {
        guard pid > 0 else { return }
        pidToBundleId[pid] = bundleId

        if observers[pid] == nil {
            var observer: AXObserver?
            let callback: AXObserverCallback = { _, element, notification, _ in
                let notif = notification as String
                var wid: CGWindowID = 0
                _ = _AXUIElementGetWindow(element, &wid)
                DispatchQueue.main.async {
                    SecretiveFocusManager.shared.handleAXEvent(element: element, wid: wid, notification: notif)
                }
            }
            if AXObserverCreate(pid, callback, &observer) == .success, let obs = observer {
                let axApp = AXUIElementCreateApplication(pid)
                let notifications: [String] = [
                    kAXWindowCreatedNotification,
                    kAXWindowDeminiaturizedNotification,
                    kAXApplicationShownNotification,
                    kAXUIElementDestroyedNotification
                ]
                for n in notifications {
                    AXObserverAddNotification(obs, axApp, n as CFString, nil)
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
                observers[pid] = obs
            }
        }

        if triggerPresentation {
            scheduleInitialPresentation(forPid: pid)
        }
    }

    private func unregisterWatchedApp(pid: pid_t) {
        pidToBundleId.removeValue(forKey: pid)
        deferredTargetDisplay.removeValue(forKey: pid)
        if let obs = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
    }

    private func registerSkyLightNotifications() {
        let cid = SLSMainConnectionID()
        let ctx = UnsafeMutableRawPointer(bitPattern: Int(cid))

        // Only listen to 0x52d (window spawned/added to space) and 0x52e (window destroyed/removed from space).
        // Do NOT listen to 0x328 (OrderWindow), because JankyBorders continuously calls OrderWindow relative to existing
        // windows whenever focus changes, which would falsely re-trigger SecretAgent activation.
        let spawnCallback: @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void = { event, data, dataLen, _, _ in
            guard let data = data, dataLen >= 12 else { return }
            let wid = data.load(fromByteOffset: 8, as: UInt32.self)
            guard wid > 0 else { return }
            let mainCid = SLSMainConnectionID()
            var ownerCid: Int32 = 0
            var pid: pid_t = 0
            _ = SLSGetWindowOwner(mainCid, wid, &ownerCid)
            _ = SLSConnectionGetPID(ownerCid, &pid)
            DispatchQueue.main.async {
                SecretiveFocusManager.shared.handleSkyLightSpawn(event: event, wid: wid, pid: pid)
            }
        }

        _ = SLSRegisterNotifyProc(spawnCallback, 0x52d, ctx)
        _ = SLSRegisterNotifyProc(spawnCallback, 0x52e, ctx)
    }

    /// Returns true whenever a native macOS authentication dialog (coreautha / SecurityAgent) is visible or active.
    /// When true, Secretive / SecretAgent must NEVER steal focus or raise above it.
    private func isNativeAuthActive() -> Bool {
        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           nativeAuthBundleIds.contains(bid) {
            lastNativeAuthSeenTime = CFAbsoluteTimeGetCurrent()
            return true
        }

        if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in infoList {
                let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
                let ownerPid = pid_t(info[kCGWindowOwnerPID as String] as? Int ?? 0)
                let isNativeAuthOwner = nativeAuthOwnerNames.contains(ownerName) ||
                    (pidToBundleId[ownerPid] != nil && nativeAuthBundleIds.contains(pidToBundleId[ownerPid]!))
                if isNativeAuthOwner {
                    let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
                    let h = (bounds["Height"] as? Double) ?? Double(bounds["Height"] as? Int ?? 0)
                    let w = (bounds["Width"] as? Double) ?? Double(bounds["Width"] as? Int ?? 0)
                    if w > 40 && h > 40 {
                        lastNativeAuthSeenTime = CFAbsoluteTimeGetCurrent()
                        return true
                    }
                }
            }
        }

        if (CFAbsoluteTimeGetCurrent() - lastNativeAuthSeenTime) < 0.25 {
            return true
        }

        return false
    }

    /// Checks whether a given window ID is physically occluded by any normal (layer 0) on-screen application window above it.
    private func occludingNormalWindowOwner(wid: UInt32, winRect: CGRect, ownPid: pid_t) -> String? {
        guard wid > 0,
              let aboveList = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], wid) as? [[String: Any]] else {
            return nil
        }
        for info in aboveList {
            let ownerPid = pid_t(info[kCGWindowOwnerPID as String] as? Int ?? 0)
            if ownerPid == ownPid { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            // Only care about normal app windows (layer == 0), never menus/popovers/borders/native auth overlays
            if layer != 0 { continue }
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            if nativeAuthOwnerNames.contains(ownerName) || ownerName == "borders" || ownerName == "JankyBorders" || ownerName == "Window Server" {
                continue
            }
            let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let x = (bounds["X"] as? Double) ?? Double(bounds["X"] as? Int ?? 0)
            let y = (bounds["Y"] as? Double) ?? Double(bounds["Y"] as? Int ?? 0)
            let w = (bounds["Width"] as? Double) ?? Double(bounds["Width"] as? Int ?? 0)
            let h = (bounds["Height"] as? Double) ?? Double(bounds["Height"] as? Int ?? 0)
            if w < 60 || h < 60 { continue }
            let otherRect = CGRect(x: x, y: y, width: w, height: h)
            let inter = winRect.intersection(otherRect)
            if !inter.isNull && (inter.width * inter.height) > 400 {
                return ownerName.isEmpty ? "pid:\(ownerPid)" : ownerName
            }
        }
        return nil
    }

    func handleSkyLightSpawn(event: UInt32, wid: UInt32, pid: pid_t) {
        if event == 0x52e {
            presentedWids.remove(wid)
            lastOccludedRaiseTime.removeValue(forKey: wid)
            return
        }
        guard isWatchedPid(pid) else { return }
        let isNativeAuth = (pidToBundleId[pid] == localAuthBundleId)
        if isNativeAuth {
            lastNativeAuthSeenTime = CFAbsoluteTimeGetCurrent()
        } else {
            guard !presentedWids.contains(wid) else { return }
        }
        scheduleInitialPresentation(forPid: pid)
    }

    func handleAXEvent(element: AXUIElement, wid: CGWindowID, notification: String) {
        if notification == kAXUIElementDestroyedNotification {
            if wid > 0 {
                presentedWids.remove(wid)
                lastOccludedRaiseTime.removeValue(forKey: wid)
            }
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard isWatchedPid(pid) else { return }
        let isNativeAuth = (pidToBundleId[pid] == localAuthBundleId)
        if isNativeAuth {
            lastNativeAuthSeenTime = CFAbsoluteTimeGetCurrent()
        } else if wid > 0 {
            guard !presentedWids.contains(wid) else { return }
        }
        scheduleInitialPresentation(forPid: pid)
    }

    private func isWatchedPid(_ pid: pid_t) -> Bool {
        if pidToBundleId[pid] != nil { return true }
        if let app = NSRunningApplication(processIdentifier: pid),
           let bid = app.bundleIdentifier,
           watchedBundleIds.contains(bid) {
            syncRunningWatchedApps()
            registerWatchedApp(pid: pid, bundleId: bid, triggerPresentation: false)
            return true
        }
        return false
    }

    private func scheduleInitialPresentation(forPid pid: pid_t) {
        let targetDisplay = getActiveDisplayBounds()
        let isNativeAuth = (pidToBundleId[pid] == localAuthBundleId)
        // coreautha (CampoLightweightUI / Apple Watch fallback) may materialize or resize its dialog up to ~3s after activation
        let delays: [Double] = isNativeAuth ? [0.0, 0.06, 0.18, 0.4, 0.85, 1.6, 2.6, 3.4] : [0.0, 0.06, 0.18, 0.35]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.presentAppWindows(pid: pid, onDisplay: targetDisplay, reason: "scheduled")
            }
        }
    }

    private func refreshExistingWindowsAtStartup() {
        syncRunningWatchedApps()
        let targetDisplay = getActiveDisplayBounds()
        for (pid, _) in pidToBundleId {
            presentAppWindows(pid: pid, onDisplay: targetDisplay, reason: "startup")
        }
    }

    private func pollSecretAgentVisibility() {
        syncRunningWatchedApps()

        // Never touch SecretAgent / Secretive while native macOS auth (coreautha / SecurityAgent) is open!
        if isNativeAuthActive() {
            return
        }

        // 1. Flush any deferred Secretive/SecretAgent presentations that were blocked while coreautha was closing
        if !deferredTargetDisplay.isEmpty {
            let pending = deferredTargetDisplay
            deferredTargetDisplay.removeAll()
            for (pid, display) in pending {
                presentAppWindows(pid: pid, onDisplay: display, reason: "deferred_after_native_auth")
            }
        }

        // 2. Guard active SecretAgent batch prompt windows against staying hidden behind normal app windows (e.g. Antigravity)
        let now = CFAbsoluteTimeGetCurrent()
        var liveSecretAgentWids: Set<UInt32> = []
        for (pid, bid) in pidToBundleId where bid == secretAgentBundleId {
            let windows = getStandardAXWindows(forPid: pid)
            for w in windows {
                var wid: CGWindowID = 0
                _ = _AXUIElementGetWindow(w, &wid)
                guard wid > 0 else { continue }

                var pos = CGPoint.zero
                var size = CGSize.zero
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success, let p = posRef {
                    AXValueGetValue(p as! AXValue, .cgPoint, &pos)
                }
                if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success, let s = sizeRef {
                    AXValueGetValue(s as! AXValue, .cgSize, &size)
                }
                if size.width < 60 || size.height < 60 { continue }

                liveSecretAgentWids.insert(wid)
                let winRect = CGRect(origin: pos, size: size)

                if !presentedWids.contains(wid) {
                    let display = getActiveDisplayBounds()
                    presentAppWindows(pid: pid, onDisplay: display, reason: "watchdog_new_batch_window")
                    return
                }

                if let occluder = occludingNormalWindowOwner(wid: wid, winRect: winRect, ownPid: pid) {
                    let lastRaise = lastOccludedRaiseTime[wid] ?? 0
                    if (now - lastRaise) >= 0.8 {
                        lastOccludedRaiseTime[wid] = now
                        let display = getActiveDisplayBounds()
                        presentAppWindows(pid: pid, onDisplay: display, reason: "occluded_by:\(occluder)")
                        return
                    }
                }
            }
        }

        // Prune closed SecretAgent window IDs so reused window IDs are always presented fresh
        if liveSecretAgentWids.isEmpty && !lastOccludedRaiseTime.isEmpty {
            for wid in Array(lastOccludedRaiseTime.keys) {
                presentedWids.remove(wid)
                lastOccludedRaiseTime.removeValue(forKey: wid)
            }
        }
    }

    private func getStandardAXWindows(forPid pid: pid_t) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }
        return windows.filter { w in
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String {
                return role == (kAXWindowRole as String) || role == "AXDialog" || role == "AXSystemDialog"
            }
            return true
        }
    }

    private func presentAppWindows(pid: pid_t, onDisplay displayBounds: CGRect, reason: String) {
        let bid = pidToBundleId[pid] ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let isNativeAuthApp = (bid == localAuthBundleId)

        // CRITICAL EXCEPTION: Never allow SecretAgent or Secretive to raise or steal focus while native macOS auth (coreautha / SecurityAgent) is open!
        // Instead of dropping the presentation permanently (which broke batch prompts spawned right as coreautha is cancelled),
        // record it as deferred so pollSecretAgentVisibility() raises it immediately once coreautha closes.
        if !isNativeAuthApp && isNativeAuthActive() {
            if deferredTargetDisplay[pid] == nil {
                logMsg("defer pid=\(pid) bid=\(bid) reason=\(reason) (native auth active)")
            }
            deferredTargetDisplay[pid] = displayBounds
            return
        }

        let windows = getStandardAXWindows(forPid: pid)
        guard !windows.isEmpty else { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }

        let axApp = AXUIElementCreateApplication(pid)
        var nativeAuthNeedsActivation = false
        var presentedAnySecretiveWindow = false

        for w in windows {
            var wid: CGWindowID = 0
            _ = _AXUIElementGetWindow(w, &wid)

            var pos = CGPoint.zero
            var size = CGSize.zero
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success,
               let p = posRef {
                AXValueGetValue(p as! AXValue, .cgPoint, &pos)
            }
            if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let s = sizeRef {
                AXValueGetValue(s as! AXValue, .cgSize, &size)
            }

            if size.width < 60 || size.height < 60 {
                continue
            }

            let effectiveW = size.width
            let effectiveH = size.height
            let winCenter = CGPoint(x: pos.x + effectiveW / 2.0, y: pos.y + effectiveH / 2.0)
            let isOnActiveDisplay = displayBounds.contains(winCenter)

            if isNativeAuthApp {
                // If coreautha is already on the active display and frontmost, leave it completely untouched
                // so password typing / Touch ID / Apple Watch interaction is never interrupted.
                if isOnActiveDisplay && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                    continue
                }
                if !isOnActiveDisplay {
                    var targetPt = CGPoint(
                        x: round(displayBounds.origin.x + (displayBounds.size.width - effectiveW) / 2.0),
                        y: round(displayBounds.origin.y + (displayBounds.size.height - effectiveH) / 2.5)
                    )
                    if abs(pos.x - targetPt.x) > 2 || abs(pos.y - targetPt.y) > 2 {
                        if let posVal = AXValueCreate(.cgPoint, &targetPt) {
                            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, posVal)
                            logMsg("move coreautha wid=\(wid) to=\(targetPt) reason=\(reason)")
                        }
                    }
                }
                // Never touch kAXFocusedAttribute on coreautha's AXWindow container so its internal password field keeps focus.
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                    nativeAuthNeedsActivation = true
                }
            } else {
                var targetPt = CGPoint(
                    x: round(displayBounds.origin.x + (displayBounds.size.width - effectiveW) / 2.0),
                    y: round(displayBounds.origin.y + (displayBounds.size.height - effectiveH) / 2.5)
                )
                if abs(pos.x - targetPt.x) > 2 || abs(pos.y - targetPt.y) > 2 {
                    if let posVal = AXValueCreate(.cgPoint, &targetPt) {
                        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, posVal)
                    }
                }
                AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                if wid > 0 {
                    presentedWids.insert(wid)
                    lastOccludedRaiseTime[wid] = CFAbsoluteTimeGetCurrent()
                }
                presentedAnySecretiveWindow = true
                logMsg("present bid=\(bid) wid=\(wid) size=\(Int(effectiveW))x\(Int(effectiveH)) onDisplay=\(displayBounds) reason=\(reason)")
            }
        }

        if !isNativeAuthApp {
            guard presentedAnySecretiveWindow else { return }
            if isNativeAuthActive() {
                deferredTargetDisplay[pid] = displayBounds
                return
            }
        }

        if presentedAnySecretiveWindow || nativeAuthNeedsActivation {
            app.activate(options: [.activateAllWindows])
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            for w in windows {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
        }
    }

    private func getActiveDisplayBounds() -> CGRect {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &displays, &displayCount)
        let activeDisplays = (0..<Int(displayCount)).map { CGDisplayBounds(displays[$0]) }
        guard !activeDisplays.isEmpty else {
            return CGDisplayBounds(CGMainDisplayID())
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        var candidatePid: pid_t = 0
        if let front = frontApp,
           let bid = front.bundleIdentifier,
           !watchedBundleIds.contains(bid),
           !nativeAuthBundleIds.contains(bid) {
            candidatePid = front.processIdentifier
        } else if lastActiveRegularPid > 0 {
            candidatePid = lastActiveRegularPid
        }

        if candidatePid > 0 {
            let axApp = AXUIElementCreateApplication(candidatePid)
            var focusedWinRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWinRef) == .success,
               let focusedWin = focusedWinRef {
                var pos = CGPoint.zero
                var size = CGSize.zero
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(focusedWin as! AXUIElement, kAXPositionAttribute as CFString, &posRef) == .success,
                   let p = posRef,
                   AXUIElementCopyAttributeValue(focusedWin as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
                   let s = sizeRef {
                    AXValueGetValue(p as! AXValue, .cgPoint, &pos)
                    AXValueGetValue(s as! AXValue, .cgSize, &size)
                    let winRect = CGRect(origin: pos, size: size)
                    let winArea = winRect.width * winRect.height
                    if winArea > 2500 {
                        for dBounds in activeDisplays {
                            let inter = winRect.intersection(dBounds)
                            if !inter.isNull && (inter.width * inter.height) > (0.5 * winArea) {
                                return dBounds
                            }
                        }
                    }
                }
            }
        }

        if let mouseLoc = CGEvent(source: nil)?.location {
            for dBounds in activeDisplays {
                if dBounds.contains(mouseLoc) {
                    return dBounds
                }
            }
        }

        return CGDisplayBounds(CGMainDisplayID())
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
SecretiveFocusManager.shared.start()
app.run()
