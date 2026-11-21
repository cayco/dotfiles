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

@_silgen_name("SLSRequestNotificationsForWindows")
func SLSRequestNotificationsForWindows(_ cid: Int32, _ windowList: UnsafePointer<UInt32>?, _ count: Int32) -> Int32

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ outWid: UnsafeMutablePointer<CGWindowID>) -> AXError

private let secretAgentBundleId = "com.maxgoedjen.Secretive.SecretAgent"
private let secretiveHostBundleId = "com.maxgoedjen.Secretive.Host"
private let localAuthBundleId = "com.apple.LocalAuthentication.UIAgent"

private let watchedBundleIds: Set<String> = [
    secretAgentBundleId,
    secretiveHostBundleId,
    localAuthBundleId
]

// Popup agents that should stay pinned to the active screen and on top while their prompt window exists
private let transientAuthBundleIds: Set<String> = [
    secretAgentBundleId,
    localAuthBundleId
]

final class SecretiveFocusManager {
    static let shared = SecretiveFocusManager()

    private var pidToBundleId: [pid_t: String] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var trackedWids: Set<UInt32> = []
    private var positionedWids: Set<UInt32> = []
    private var lastRaiseTime: [UInt32: CFAbsoluteTime] = [:]
    private var lastActiveRegularPid: pid_t = 0
    private var watchdogTimer: Timer?

    func start() {
        let ws = NSWorkspace.shared
        if let front = ws.frontmostApplication,
           let bid = front.bundleIdentifier,
           !watchedBundleIds.contains(bid) {
            lastActiveRegularPid = front.processIdentifier
        }

        for app in ws.runningApplications {
            if let bid = app.bundleIdentifier, watchedBundleIds.contains(bid) {
                registerWatchedApp(pid: app.processIdentifier, bundleId: bid)
            }
        }

        let nc = ws.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier,
                  watchedBundleIds.contains(bid) else { return }
            self?.registerWatchedApp(pid: app.processIdentifier, bundleId: bid)
        }

        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.unregisterWatchedApp(pid: app.processIdentifier)
        }

        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bid = app.bundleIdentifier ?? ""
            if !watchedBundleIds.contains(bid) {
                self.lastActiveRegularPid = app.processIdentifier
                // If a transient auth popup (SecretAgent / LocalAuthentication) is still open, keep it on top
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self.enforceTransientPopupsOnTop(forceRecenter: false)
                }
            }
        }

        registerSkyLightNotifications()
        refreshTrackedWindowsAndEnforce(forceRecenter: true)
    }

    private func registerWatchedApp(pid: pid_t, bundleId: String) {
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
                    kAXMainWindowChangedNotification,
                    kAXFocusedWindowChangedNotification,
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

        scheduleBurstEnforcement(forPid: pid, forceRecenter: true)
    }

    private func unregisterWatchedApp(pid: pid_t) {
        pidToBundleId.removeValue(forKey: pid)
        if let obs = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        updateWatchdogTimer()
    }

    private func registerSkyLightNotifications() {
        let cid = SLSMainConnectionID()
        let ctx = UnsafeMutableRawPointer(bitPattern: Int(cid))

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

        let modifyCallback: @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void = { event, data, dataLen, _, _ in
            guard let data = data, dataLen >= 4 else { return }
            let wid = data.load(as: UInt32.self)
            guard wid > 0 else { return }
            let mainCid = SLSMainConnectionID()
            var ownerCid: Int32 = 0
            var pid: pid_t = 0
            _ = SLSGetWindowOwner(mainCid, wid, &ownerCid)
            _ = SLSConnectionGetPID(ownerCid, &pid)
            DispatchQueue.main.async {
                SecretiveFocusManager.shared.handleSkyLightModify(event: event, wid: wid, pid: pid)
            }
        }

        // 0x52d = Window spawned / added to space, 0x52e = Window destroyed / removed from space
        _ = SLSRegisterNotifyProc(spawnCallback, 0x52d, ctx)
        _ = SLSRegisterNotifyProc(spawnCallback, 0x52e, ctx)

        // 0x328 = Window ordered in, 0x32f = Window unhidden, 0x330 = Window hidden, 0x324 = Window destroyed
        _ = SLSRegisterNotifyProc(modifyCallback, 0x328, ctx)
        _ = SLSRegisterNotifyProc(modifyCallback, 0x32f, ctx)
        _ = SLSRegisterNotifyProc(modifyCallback, 0x330, ctx)
        _ = SLSRegisterNotifyProc(modifyCallback, 0x324, ctx)
        _ = SLSRegisterNotifyProc(modifyCallback, 0x52a, ctx)
        _ = SLSRegisterNotifyProc(modifyCallback, 0x2d3, ctx)
    }

    private func updateSkyLightWindowSubscription() {
        let cid = SLSMainConnectionID()
        let arr = Array(trackedWids)
        if arr.isEmpty {
            _ = SLSRequestNotificationsForWindows(cid, nil, 0)
        } else {
            arr.withUnsafeBufferPointer { buf in
                _ = SLSRequestNotificationsForWindows(cid, buf.baseAddress, Int32(buf.count))
            }
        }
    }

    func handleSkyLightSpawn(event: UInt32, wid: UInt32, pid: pid_t) {
        if event == 0x52e {
            trackedWids.remove(wid)
            positionedWids.remove(wid)
            lastRaiseTime.removeValue(forKey: wid)
            updateSkyLightWindowSubscription()
            updateWatchdogTimer()
            return
        }
        guard isWatchedPid(pid) else { return }
        let isNew = !trackedWids.contains(wid)
        trackedWids.insert(wid)
        updateSkyLightWindowSubscription()
        scheduleBurstEnforcement(forPid: pid, forceRecenter: isNew)
    }

    func handleSkyLightModify(event: UInt32, wid: UInt32, pid: pid_t) {
        if event == 0x324 || event == 0x330 {
            trackedWids.remove(wid)
            positionedWids.remove(wid)
            lastRaiseTime.removeValue(forKey: wid)
            updateSkyLightWindowSubscription()
            updateWatchdogTimer()
            return
        }
        guard isWatchedPid(pid) else { return }
        let isNew = !trackedWids.contains(wid)
        trackedWids.insert(wid)
        updateSkyLightWindowSubscription()

        let now = CFAbsoluteTimeGetCurrent()
        if !isNew, let last = lastRaiseTime[wid], (now - last) < 0.35 {
            return
        }
        scheduleBurstEnforcement(forPid: pid, forceRecenter: isNew)
    }

    func handleAXEvent(element: AXUIElement, wid: CGWindowID, notification: String) {
        if notification == kAXUIElementDestroyedNotification {
            if wid > 0 {
                trackedWids.remove(wid)
                positionedWids.remove(wid)
                lastRaiseTime.removeValue(forKey: wid)
                updateSkyLightWindowSubscription()
            }
            updateWatchdogTimer()
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard isWatchedPid(pid) else { return }
        let isNew = (notification == kAXWindowCreatedNotification) || (wid > 0 && !positionedWids.contains(wid))
        if wid > 0 {
            trackedWids.insert(wid)
            updateSkyLightWindowSubscription()
        }
        scheduleBurstEnforcement(forPid: pid, forceRecenter: isNew)
    }

    private func isWatchedPid(_ pid: pid_t) -> Bool {
        if pidToBundleId[pid] != nil { return true }
        if let app = NSRunningApplication(processIdentifier: pid),
           let bid = app.bundleIdentifier,
           watchedBundleIds.contains(bid) {
            pidToBundleId[pid] = bid
            return true
        }
        return false
    }

    private func scheduleBurstEnforcement(forPid pid: pid_t, forceRecenter: Bool) {
        let targetDisplay = getActiveDisplayBounds()
        for delay in [0.0, 0.06, 0.18] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.presentAppWindows(pid: pid, onDisplay: targetDisplay, forceRecenter: forceRecenter)
                self.updateWatchdogTimer()
            }
        }
    }

    private func refreshTrackedWindowsAndEnforce(forceRecenter: Bool) {
        let targetDisplay = getActiveDisplayBounds()
        for (pid, _) in pidToBundleId {
            presentAppWindows(pid: pid, onDisplay: targetDisplay, forceRecenter: forceRecenter)
        }
        updateWatchdogTimer()
    }

    private func enforceTransientPopupsOnTop(forceRecenter: Bool) {
        let targetDisplay = getActiveDisplayBounds()
        // If LocalAuthentication (coreautha) has a window, it takes top priority over SecretAgent
        if let authPid = pidToBundleId.first(where: { $0.value == localAuthBundleId })?.key,
           !getStandardAXWindows(forPid: authPid).isEmpty {
            presentAppWindows(pid: authPid, onDisplay: targetDisplay, forceRecenter: forceRecenter)
            return
        }
        if let agentPid = pidToBundleId.first(where: { $0.value == secretAgentBundleId })?.key,
           !getStandardAXWindows(forPid: agentPid).isEmpty {
            presentAppWindows(pid: agentPid, onDisplay: targetDisplay, forceRecenter: forceRecenter)
        }
    }

    private func updateWatchdogTimer() {
        var hasTransientWindows = false
        for (pid, bid) in pidToBundleId where transientAuthBundleIds.contains(bid) {
            if !getStandardAXWindows(forPid: pid).isEmpty {
                hasTransientWindows = true
                break
            }
        }

        if hasTransientWindows {
            if watchdogTimer == nil {
                watchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    self?.enforceTransientPopupsOnTop(forceRecenter: false)
                    self?.updateWatchdogTimer()
                }
            }
        } else {
            watchdogTimer?.invalidate()
            watchdogTimer = nil
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

    private func isWindowTopmost(_ wid: CGWindowID) -> Bool {
        guard wid > 0,
              let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in infoList {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "borders" || owner == "SketchyBar" || layer != 0 {
                continue
            }
            let topWid = CGWindowID(info[kCGWindowNumber as String] as? Int ?? 0)
            return topWid == wid
        }
        return false
    }

    private func presentAppWindows(pid: pid_t, onDisplay displayBounds: CGRect, forceRecenter: Bool) {
        let windows = getStandardAXWindows(forPid: pid)
        guard !windows.isEmpty else { return }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }

        // If presenting SecretAgent while LocalAuthentication (coreautha) already has an active dialog, let coreautha stay above SecretAgent
        if pidToBundleId[pid] == secretAgentBundleId,
           let authPid = pidToBundleId.first(where: { $0.value == localAuthBundleId })?.key,
           !getStandardAXWindows(forPid: authPid).isEmpty {
            return
        }

        let axApp = AXUIElementCreateApplication(pid)
        var needsActivation = (NSWorkspace.shared.frontmostApplication?.processIdentifier != pid)

        for w in windows {
            var wid: CGWindowID = 0
            _ = _AXUIElementGetWindow(w, &wid)
            if wid > 0 && !trackedWids.contains(wid) {
                trackedWids.insert(wid)
                updateSkyLightWindowSubscription()
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
            let isFirstPositioning = (wid == 0) || !positionedWids.contains(wid)

            if forceRecenter || isFirstPositioning || !isOnActiveDisplay {
                var targetPt = CGPoint(
                    x: round(displayBounds.origin.x + (displayBounds.size.width - effectiveW) / 2.0),
                    y: round(displayBounds.origin.y + (displayBounds.size.height - effectiveH) / 2.5)
                )
                if abs(pos.x - targetPt.x) > 2 || abs(pos.y - targetPt.y) > 2 {
                    if let posVal = AXValueCreate(.cgPoint, &targetPt) {
                        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, posVal)
                    }
                }
                if wid > 0 && size.width >= 50 {
                    positionedWids.insert(wid)
                }
            }

            let topmost = (wid > 0) ? isWindowTopmost(wid) : false
            if !topmost || needsActivation || forceRecenter || isFirstPositioning {
                needsActivation = true
                if wid > 0 {
                    lastRaiseTime[wid] = CFAbsoluteTimeGetCurrent()
                }
                AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
        }

        if needsActivation {
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

        // 1. If a non-watched app is currently frontmost and has a genuinely visible focused window (>50% on a display), use that display
        let frontApp = NSWorkspace.shared.frontmostApplication
        var candidatePid: pid_t = 0
        if let front = frontApp,
           let bid = front.bundleIdentifier,
           !watchedBundleIds.contains(bid) {
            candidatePid = front.processIdentifier
        } else if lastActiveRegularPid > 0 {
            candidatePid = lastActiveRegularPid
        }

        if frontApp == nil || !(watchedBundleIds.contains(frontApp?.bundleIdentifier ?? "")),
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

        // 2. Fall back to the display containing the mouse cursor
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
