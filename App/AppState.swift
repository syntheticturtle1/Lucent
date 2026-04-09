import Foundation
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox
import LucentCore

@MainActor
public final class AppState: ObservableObject {
    @Published public var pipeline = TrackingPipeline()
    @Published public var permissions = Permissions()
    @Published public var showSettings = false
    @Published public var showCalibration = false
    @Published public var hasCompletedOnboarding: Bool
    @Published public var showHUD: Bool
    @Published public var hudExpanded: Bool
    @Published public var handGesturesEnabled: Bool
    @Published public var keyboardModeEnabled: Bool

    private var hotkeyRef: EventHotKeyRef?
    private var hudHotkeyRef: EventHotKeyRef?
    private var keyboardHotkeyRef: EventHotKeyRef?

    public init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.showHUD = UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true
        self.hudExpanded = UserDefaults.standard.bool(forKey: "hudExpanded")
        self.handGesturesEnabled = UserDefaults.standard.object(forKey: "handGesturesEnabled") as? Bool ?? true
        self.keyboardModeEnabled = UserDefaults.standard.object(forKey: "keyboardModeEnabled") as? Bool ?? false
        registerGlobalHotkeys()
    }

    public func toggleTracking() {
        do { try pipeline.toggle() } catch { print("Failed to toggle tracking: \(error)") }
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    public func toggleHUDExpanded() {
        hudExpanded.toggle()
        UserDefaults.standard.set(hudExpanded, forKey: "hudExpanded")
    }

    public func toggleHandGestures() {
        handGesturesEnabled.toggle()
        pipeline.handGesturesEnabled = handGesturesEnabled
        UserDefaults.standard.set(handGesturesEnabled, forKey: "handGesturesEnabled")
    }

    public func toggleKeyboardMode() {
        guard keyboardModeEnabled else { return }
        pipeline.toggleKeyboardMode()
    }

    public func setKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "keyboardModeEnabled")
        if !enabled && pipeline.keyboardModeActive {
            pipeline.toggleKeyboardMode()  // Exit keyboard mode if disabling
        }
    }

    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { print("Failed to set launch at login: \(error)") }
        }
    }

    private func registerGlobalHotkeys() {
        // Hotkey 1: Cmd+Shift+L -- Toggle tracking
        var trackingHotKeyID = EventHotKeyID()
        trackingHotKeyID.signature = OSType(0x4C554345)
        trackingHotKeyID.id = 1
        var ref1: EventHotKeyRef?
        RegisterEventHotKey(0x25, UInt32(cmdKey | shiftKey), trackingHotKeyID, GetApplicationEventTarget(), 0, &ref1)
        hotkeyRef = ref1

        // Hotkey 2: Cmd+Shift+H -- Toggle HUD
        var hudHotKeyID = EventHotKeyID()
        hudHotKeyID.signature = OSType(0x4C554345)
        hudHotKeyID.id = 2
        var ref2: EventHotKeyRef?
        RegisterEventHotKey(0x04, UInt32(cmdKey | shiftKey), hudHotKeyID, GetApplicationEventTarget(), 0, &ref2)
        hudHotkeyRef = ref2

        // Hotkey 3: Cmd+Shift+K -- Toggle keyboard mode
        var keyboardHotKeyID = EventHotKeyID()
        keyboardHotKeyID.signature = OSType(0x4C554345)
        keyboardHotKeyID.id = 3
        var ref3: EventHotKeyRef?
        RegisterEventHotKey(0x28, UInt32(cmdKey | shiftKey), keyboardHotKeyID, GetApplicationEventTarget(), 0, &ref3)
        keyboardHotkeyRef = ref3

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                            EventParamType(typeEventHotKeyID), nil,
                            MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            switch hotKeyID.id {
            case 1: NotificationCenter.default.post(name: .toggleTracking, object: nil)
            case 2: NotificationCenter.default.post(name: .toggleHUD, object: nil)
            case 3: NotificationCenter.default.post(name: .toggleKeyboard, object: nil)
            default: break
            }
            return noErr
        }, 1, &eventType, nil, nil)

        NotificationCenter.default.addObserver(forName: .toggleTracking, object: nil, queue: .main) { [weak self] _ in self?.toggleTracking() }
        NotificationCenter.default.addObserver(forName: .toggleHUD, object: nil, queue: .main) { [weak self] _ in self?.toggleHUDExpanded() }
        NotificationCenter.default.addObserver(forName: .toggleKeyboard, object: nil, queue: .main) { [weak self] _ in self?.toggleKeyboardMode() }
    }
}

extension Notification.Name {
    static let toggleTracking = Notification.Name("com.lucent.toggleTracking")
    static let toggleHUD = Notification.Name("com.lucent.toggleHUD")
    static let toggleKeyboard = Notification.Name("com.lucent.toggleKeyboard")
}
