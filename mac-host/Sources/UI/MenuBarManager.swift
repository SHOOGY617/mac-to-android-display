import AppKit

public final class ResolutionItemData: NSObject {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var statsMenuItem: NSMenuItem?
    
    // Callbacks for live pipeline control
    public var onResolutionChanged: ((Int, Int) -> Void)?
    public var onRefreshRateChanged: ((Int32) -> Void)?
    public var onCodecChanged: ((VideoCodec) -> Void)?
    public var onAudioToggled: ((Bool) -> Void)?
    public var onQuitRequested: (() -> Void)?
    
    // Current state
    private var isConnected: Bool = false
    private var currentWidth: Int
    private var currentHeight: Int
    private var currentFPS: Int32
    private var currentCodec: VideoCodec
    private var isAudioEnabled: Bool
    
    public init(
        initialWidth: Int = 2560,
        initialHeight: Int = 1600,
        initialFPS: Int32 = 120,
        initialCodec: VideoCodec = .hevc,
        audioEnabled: Bool = true
    ) {
        self.currentWidth = initialWidth
        self.currentHeight = initialHeight
        self.currentFPS = initialFPS
        self.currentCodec = initialCodec
        self.isAudioEnabled = audioEnabled
        super.init()
    }
    
    public func setup() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            NSApplication.shared.setActivationPolicy(.accessory)
            
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "ipad.landscape", accessibilityDescription: "Tab S7 Display") {
                    img.isTemplate = true
                    button.image = img
                } else {
                    button.title = "🖥️ Tab S7"
                }
                button.toolTip = "Galaxy Tab S7 Extended Display"
            }
            
            self.statusItem = item
            self.rebuildMenu()
        }
    }
    
    public func updateConnectionStatus(connected: Bool) {
        self.isConnected = connected
        DispatchQueue.main.async { [weak self] in
            self?.rebuildMenu()
        }
    }
    
    public func updateStats(fps: Int32, codec: VideoCodec, width: Int, height: Int) {
        self.currentFPS = fps
        self.currentCodec = codec
        self.currentWidth = width
        self.currentHeight = height
        DispatchQueue.main.async { [weak self] in
            self?.rebuildMenu()
        }
    }
    
    private func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        
        // 1. Connection Header
        let statusTitle = isConnected ? "🟢 Connected to Galaxy Tab S7" : "⚪️ Waiting for Tablet (USB)..."
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        self.statusMenuItem = statusItem
        
        // 2. Active Specs
        let isPortrait = currentHeight > currentWidth
        let orientationStr = isPortrait ? "Portrait" : "Landscape"
        let statsTitle = "    \(currentFPS) FPS • \(currentCodec.rawValue.uppercased()) • \(orientationStr) • \(isAudioEnabled ? "Audio On" : "Audio Off")"
        let statsItem = NSMenuItem(title: statsTitle, action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        self.statsMenuItem = statsItem
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Resolution / UI Scaling Submenu
        let resMenu = NSMenu()
        let isDefaultLandscape = currentWidth == 2560 && currentHeight == 1600
        let isDefaultPortrait = currentWidth == 1600 && currentHeight == 2560
        
        addResolutionItem(to: resMenu, title: "Default Landscape (1280x800 Retina)", width: 2560, height: 1600, isChecked: isDefaultLandscape)
        addResolutionItem(to: resMenu, title: "More Space (1440x900 Retina)", width: 2880, height: 1800, isChecked: currentWidth == 2880 && currentHeight == 1800)
        addResolutionItem(to: resMenu, title: "Max Space (1600x1000 Retina)", width: 3200, height: 2000, isChecked: currentWidth == 3200 && currentHeight == 2000)
        addResolutionItem(to: resMenu, title: "Default Portrait (800x1280 Retina)", width: 1600, height: 2560, isChecked: isDefaultPortrait)
        
        let resSubmenuItem = NSMenuItem(title: "Resolution & Scaling", action: nil, keyEquivalent: "")
        resSubmenuItem.submenu = resMenu
        menu.addItem(resSubmenuItem)
        
        // 4. Refresh Rate Submenu
        let fpsMenu = NSMenu()
        addFPSItem(to: fpsMenu, title: "120 FPS (ProMotion Fluid)", fps: 120, isChecked: currentFPS == 120)
        addFPSItem(to: fpsMenu, title: "60 FPS (Standard)", fps: 60, isChecked: currentFPS == 60)
        
        let fpsSubmenuItem = NSMenuItem(title: "Refresh Rate", action: nil, keyEquivalent: "")
        fpsSubmenuItem.submenu = fpsMenu
        menu.addItem(fpsSubmenuItem)
        
        // 5. Codec Submenu
        let codecMenu = NSMenu()
        addCodecItem(to: codecMenu, title: "H.265 / HEVC (Ultra Crisp Text)", codec: .hevc, isChecked: currentCodec == .hevc)
        addCodecItem(to: codecMenu, title: "H.264 / AVC (Standard)", codec: .h264, isChecked: currentCodec == .h264)
        
        let codecSubmenuItem = NSMenuItem(title: "Video Codec", action: nil, keyEquivalent: "")
        codecSubmenuItem.submenu = codecMenu
        menu.addItem(codecSubmenuItem)
        
        // 6. Audio Toggle
        let audioItem = NSMenuItem(
            title: isAudioEnabled ? "✓ Stream Mac Audio to Tablet" : "Stream Mac Audio to Tablet",
            action: #selector(toggleAudio),
            keyEquivalent: ""
        )
        audioItem.target = self
        menu.addItem(audioItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 7. ADB Reverse Quick Action
        let adbItem = NSMenuItem(title: "Run 'adb reverse tcp:8080'", action: #selector(runAdbReverse), keyEquivalent: "r")
        adbItem.target = self
        menu.addItem(adbItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 8. Quit
        let quitItem = NSMenuItem(title: "Quit MacDisplayHost", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        item.menu = menu
    }
    
    private func addResolutionItem(to menu: NSMenu, title: String, width: Int, height: Int, isChecked: Bool) {
        let item = NSMenuItem(title: (isChecked ? "✓ " : "   ") + title, action: #selector(selectResolution(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ResolutionItemData(width: width, height: height)
        menu.addItem(item)
    }
    
    private func addFPSItem(to menu: NSMenu, title: String, fps: Int32, isChecked: Bool) {
        let item = NSMenuItem(title: (isChecked ? "✓ " : "   ") + title, action: #selector(selectFPS(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = NSNumber(value: fps)
        menu.addItem(item)
    }
    
    private func addCodecItem(to menu: NSMenu, title: String, codec: VideoCodec, isChecked: Bool) {
        let item = NSMenuItem(title: (isChecked ? "✓ " : "   ") + title, action: #selector(selectCodec(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = codec.rawValue as NSString
        menu.addItem(item)
    }
    
    @objc private func selectResolution(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? ResolutionItemData else { return }
        self.currentWidth = data.width
        self.currentHeight = data.height
        onResolutionChanged?(data.width, data.height)
        rebuildMenu()
    }
    
    @objc private func selectFPS(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let fps = num.int32Value
        self.currentFPS = fps
        onRefreshRateChanged?(fps)
        rebuildMenu()
    }
    
    @objc private func selectCodec(_ sender: NSMenuItem) {
        guard let str = sender.representedObject as? NSString, let c = VideoCodec(rawValue: str as String) else { return }
        self.currentCodec = c
        onCodecChanged?(c)
        rebuildMenu()
    }
    
    @objc private func toggleAudio() {
        self.isAudioEnabled.toggle()
        onAudioToggled?(isAudioEnabled)
        rebuildMenu()
    }
    
    @objc private func runAdbReverse() {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["adb", "reverse", "tcp:8080", "tcp:8080"]
            try? task.run()
            task.waitUntilExit()
            print("[MenuBar] 'adb reverse tcp:8080 tcp:8080' executed with status: \(task.terminationStatus)")
        }
    }
    
    @objc private func quitApp() {
        print("\n[MenuBar] Quit requested by user.")
        onQuitRequested?()
    }
}
