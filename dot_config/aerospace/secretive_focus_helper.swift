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

final class SecretiveFocusManager {
    static let shared = SecretiveFocusManager()

    private var pidToBundleId: [pid_t: String] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var handledWids: Set<UInt32> = []
    private var lastActiveRegularPid: pid_t = 0
    private var lastNativeAuthSeenTime: CFAbsoluteTime = 0

    func start() {
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
            } else if !watchedBundleIds.contains(bid) {
                self.lastActiveRegularPid = app.processIdentifier
            }
        }

        registerSkyLightNotifications()
        refreshExistingWindowsAtStartup()
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

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: localAuthBundleId) where !app.isTerminated {
            if !getStandardAXWindows(forPid: app.processIdentifier).isEmpty {
                lastNativeAuthSeenTime = CFAbsoluteTimeGetCurrent()
                return true
            }
        }

        if (CFAbsoluteTimeGetCurrent() - lastNativeAuthSeenTime) < 0.45 {
            return true
        }

        return false
    }

    func handleSkyLightSpawn(event: UInt32, wid: UInt32, pid: pid_t) {
        if event == 0x52e {
            handledWids.remove(wid)
            return
        }
        guard isWatchedPid(pid) else { return }
        if pidToBundleId[pid] == localAuthBundleId {
            lastNativeAuthSeenTime = CFAbsoluteTimeGetCurrent()
        }
        // Only trigger presentation once per newly-created/shown window ID
        guard !handledWids.contains(wid) else { return }
        handledWids.insert(wid)
        scheduleInitialPresentation(forPid: pid)
    }

    func handleAXEvent(element: AXUIElement, wid: CGWindowID, notification: String) {
        if notification == kAXUIElementDestroyedNotification {
            if wid > 0 {
                handledWids.remove(wid)
            }
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard isWatchedPid(pid) else { return }
        if pidToBundleId[pid] == localAuthBundleId {
            lastNativeAuthSeenTime = CFAbsoluteTimeGetCurrent()
        }
        if wid > 0 {
            guard !handledWids.contains(wid) else { return }
            handledWids.insert(wid)
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
        for delay in [0.0, 0.06, 0.18] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.presentAppWindows(pid: pid, onDisplay: targetDisplay)
            }
        }
    }

    private func refreshExistingWindowsAtStartup() {
        syncRunningWatchedApps()
        let targetDisplay = getActiveDisplayBounds()
        for (pid, _) in pidToBundleId {
            presentAppWindows(pid: pid, onDisplay: targetDisplay)
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
                return role == (kAXWindowRole as String)
            }
            return true
        }
    }

    private func presentAppWindows(pid: pid_t, onDisplay displayBounds: CGRect) {
        let bid = pidToBundleId[pid] ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""

        // CRITICAL EXCEPTION: Never allow SecretAgent or Secretive to raise or steal focus while native macOS auth (coreautha / SecurityAgent) is open!
        if bid != localAuthBundleId && isNativeAuthActive() {
            return
        }

        let windows = getStandardAXWindows(forPid: pid)
        guard !windows.isEmpty else { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }

        let isNativeAuthApp = (bid == localAuthBundleId)
        let axApp = AXUIElementCreateApplication(pid)

        for w in windows {
            var wid: CGWindowID = 0
            _ = _AXUIElementGetWindow(w, &wid)
            if wid > 0 {
                handledWids.insert(wid)
            }

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

            let effectiveW = size.width >= 50 ? size.width : 360.0
            let effectiveH = size.height >= 50 ? size.height : 240.0
            let winCenter = CGPoint(x: pos.x + effectiveW / 2.0, y: pos.y + effectiveH / 2.0)
            let isOnActiveDisplay = displayBounds.contains(winCenter)

            if (isNativeAuthApp && !isOnActiveDisplay) || !isNativeAuthApp {
                var targetPt = CGPoint(
                    x: round(displayBounds.origin.x + (displayBounds.size.width - effectiveW) / 2.0),
                    y: round(displayBounds.origin.y + (displayBounds.size.height - effectiveH) / 2.5)
                )
                if abs(pos.x - targetPt.x) > 2 || abs(pos.y - targetPt.y) > 2 {
                    if let posVal = AXValueCreate(.cgPoint, &targetPt) {
                        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, posVal)
                    }
                }
            }

            // For native macOS auth (coreautha), never touch kAXFocusedAttribute on the AXWindow container
            // so its internal password AXSecureTextField retains keyboard focus.
            if isNativeAuthApp {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            } else {
                AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
        }

        if !isNativeAuthApp && isNativeAuthActive() {
            return
        }

        if !isNativeAuthApp || NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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

        if frontApp == nil || (!(watchedBundleIds.contains(frontApp?.bundleIdentifier ?? "")) && !(nativeAuthBundleIds.contains(frontApp?.bundleIdentifier ?? ""))),
           candidatePid > 0 {
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
