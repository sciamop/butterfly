import Cocoa
import CoreGraphics
import Carbon

class KeyboardEngine {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isEnabled: Bool = false

    private var lastKeyCode: CGKeyCode?
    private var lastKeyTimestamp: TimeInterval = 0
    private var typingBuffer: String = ""

    var hardBounceThreshold: Double = 0.040 // 40ms in seconds
    var softBounceThreshold: Double = 0.100 // 100ms in seconds

    // Keys that move the cursor or otherwise invalidate what we think the current word is
    private let bufferResetKeyCodes: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Escape, kVK_ForwardDelete
    ]

    private let wordList: WordList
    var onEventBlocked: (() -> Void)?

    init() {
        self.wordList = WordList()
        loadSettings()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard

        let hardBounce = defaults.double(forKey: "hardBounceThreshold")
        if hardBounce > 0 {
            self.hardBounceThreshold = hardBounce
        }

        let softBounce = defaults.double(forKey: "softBounceThreshold")
        if softBounce > 0 {
            self.softBounceThreshold = softBounce
        }
    }

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func start(promptForPermission: Bool = true) -> Bool {
        guard !isEnabled else { return true }

        guard KeyboardEngine.hasAccessibilityPermission(prompt: promptForPermission) else {
            return false
        }

        // Mouse clicks move the cursor, so we watch them too in order to reset the word buffer
        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let engine = Unmanaged<KeyboardEngine>.fromOpaque(refcon!).takeUnretainedValue()
                return engine.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else {
            print("Error: Failed to create event tap. Make sure accessibility permissions are granted.")
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source = runLoopSource else {
            print("Error: Failed to create run loop source")
            CFMachPortInvalidate(tap)
            eventTap = nil
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isEnabled = true
        print("Keyboard engine started")
        return true
    }

    func stop() {
        guard isEnabled else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isEnabled = false

        // Reset state
        lastKeyCode = nil
        lastKeyTimestamp = 0
        typingBuffer = ""

        print("Keyboard engine stopped")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that are slow or interrupted; without this, filtering silently stops
            if let tap = eventTap, isEnabled {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown, .rightMouseDown:
            resetTypingState()
            return Unmanaged.passUnretained(event)
        case .keyDown:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        // Holding a key down is intentional; never treat key repeat as a bounce
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        // CGEvent.timestamp is not in nanoseconds on every Mac; NSEvent normalizes it to seconds
        let timestamp = NSEvent(cgEvent: event)?.timestamp ?? ProcessInfo.processInfo.systemUptime
        let flags = event.flags

        // Update typing buffer (includes this key, so the dictionary check sees the candidate word)
        let appendedToBuffer = updateTypingBuffer(keyCode: keyCode, flags: flags)

        // Check if this is a potential double-press
        if let lastKey = lastKeyCode, lastKey == keyCode {
            let deltaTime = timestamp - lastKeyTimestamp

            // Hard bounce: definitely block
            if deltaTime < hardBounceThreshold {
                return block(timestamp: timestamp, removeFromBuffer: appendedToBuffer)
            }

            // Suspicious zone: block only if the doubled letter can't be part of a real word
            if deltaTime < softBounceThreshold && appendedToBuffer && !wordList.isValidPrefix(typingBuffer) {
                return block(timestamp: timestamp, removeFromBuffer: true)
            }
        }

        // Update last key state
        lastKeyCode = keyCode
        lastKeyTimestamp = timestamp

        return Unmanaged.passUnretained(event)
    }

    private func block(timestamp: TimeInterval, removeFromBuffer: Bool) -> Unmanaged<CGEvent>? {
        // The character never reaches the app, so it shouldn't stay in our view of the word either
        if removeFromBuffer && !typingBuffer.isEmpty {
            typingBuffer.removeLast()
        }
        lastKeyTimestamp = timestamp
        onEventBlocked?()
        return nil
    }

    private func resetTypingState() {
        typingBuffer = ""
        lastKeyCode = nil
    }

    /// Returns true if a letter was appended to the typing buffer.
    private func updateTypingBuffer(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        if keyCode == CGKeyCode(kVK_Delete) {
            if !typingBuffer.isEmpty {
                typingBuffer.removeLast()
            }
            return false
        }

        if bufferResetKeyCodes.contains(Int(keyCode)) || flags.contains(.maskCommand) || flags.contains(.maskControl) {
            typingBuffer = ""
            return false
        }

        guard let char = character(for: keyCode, flags: flags) else {
            return false
        }

        if char.isLetter {
            typingBuffer.append(char)
            return true
        }

        // Separators, digits and anything else end the current word
        typingBuffer = ""
        return false
    }

    private func character(for keyCode: CGKeyCode, flags: CGEventFlags) -> Character? {
        // TISCopyCurrentKeyboardLayoutInputSource works even when an input method (e.g. Pinyin) is active
        guard let keyboard = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        // UCKeyTranslate expects Carbon modifier bits shifted right by 8
        var modifiers: UInt32 = 0
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey >> 8) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey >> 8) }
        if flags.contains(.maskAlphaShift) { modifiers |= UInt32(alphaLock >> 8) }

        let layout = unsafeBitCast(layoutData, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(layout) else { return nil }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutBytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyLayout in
            UCKeyTranslate(
                keyLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                modifiers,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).first
    }
}
