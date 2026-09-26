// Monitor Brightness for macOS
// Pixel-art brightness controller for the built-in display and external monitors.
// Build: ./install.sh  (needs Xcode Command Line Tools: xcode-select --install)

import Cocoa
import AVFoundation
import ServiceManagement

// MARK: - Brightness backends

// Built-in display: private DisplayServices framework (same one the keyboard brightness keys use)
private typealias DSGetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DSSetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
private let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
private let dsGet: DSGetFn? = displayServices.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: DSGetFn.self) }
private let dsSet: DSSetFn? = displayServices.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: DSSetFn.self) }

enum Brightness {
    static func displays() -> [CGDirectDisplayID] {
        var n: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetOnlineDisplayList(n, &ids, &n)
        return Array(ids.prefix(Int(n)))
    }

    /// Current level of the built-in panel, if this Mac has one we can read.
    static func builtIn() -> Int? {
        guard let get = dsGet else { return nil }
        for d in displays() where CGDisplayIsBuiltin(d) != 0 {
            var v: Float = 0
            if get(d, &v) == 0 { return Int((v * 100).rounded()) }
        }
        return nil
    }

    /// Built-in panel: real backlight. External monitors: gamma (works on any monitor, no DDC/CI needed).
    static func set(_ pct: Int) {
        let f = Float(max(0, min(100, pct))) / 100
        for d in displays() {
            if CGDisplayIsBuiltin(d) != 0, let s = dsSet, s(d, f) == 0 { continue }
            // Keep 10% floor so an external screen never goes completely black
            let top = CGGammaValue(0.1 + 0.9 * f)
            CGSetDisplayTransferByFormula(d, 0, top, 1, 0, top, 1, 0, top, 1)
        }
    }
}

// MARK: - Settings

struct Settings: Codable {
    var presets: [Int?] = [nil, nil, nil]
    var sound = true
    var applied = 100

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MonitorBrightness", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }
    static func load() -> Settings {
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }
    func save() { if let d = try? JSONEncoder().encode(self) { try? d.write(to: Settings.url) } }
}

// MARK: - Pixel drawing

func C(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
}
func lerp(_ a: (Int, Int, Int), _ b: (Int, Int, Int), _ t: Double) -> CGColor {
    C(a.0 + Int(Double(b.0 - a.0) * t), a.1 + Int(Double(b.1 - a.1) * t), a.2 + Int(Double(b.2 - a.2) * t))
}

/// Bitmap with a top-left origin, antialiasing off: every fill lands on whole pixels.
final class Canvas {
    let w: Int, h: Int, ctx: CGContext
    init(_ w: Int, _ h: Int) {
        self.w = w; self.h = h
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(false); ctx.interpolationQuality = .none
    }
    func px(_ c: CGColor, _ x: Int, _ y: Int, _ ww: Int = 1, _ hh: Int = 1) {
        ctx.setFillColor(c); ctx.fill(CGRect(x: x, y: y, width: ww, height: hh))
    }
    func image() -> CGImage { ctx.makeImage()! }
}

let bulbRows: [[Character]] = [
    "................",
    ".....OOOOOO.....",
    "...OOGGGGGGOO...",
    "..OGGHHGGGGGGO..",
    "..OGHGGGGGGGGO..",
    ".OGHGGGGGGGGGGO.",
    ".OGHGGGGGGGGGGO.",
    ".OGGGGGGGGGGGGO.",
    ".OGGGGFGGFGGGGO.",
    "..OGGGFGGFGGGO..",
    "..OGGGGFFGGGGO..",
    "...OGGGFFGGGO...",
    "....OGGFFGGO....",
    "....OGGFFGGO....",
    ".....BBBBBB.....",
    ".....DDDDDD.....",
    ".....BBBBBB.....",
    "......DDDD......",
    "................",
    "................",
].map { Array($0) }
let rays: [[(Int, Int)]] = [
    [(11, 0), (12, 0), (11, 1), (12, 1)], [(5, 2), (6, 3)], [(18, 2), (17, 3)],
    [(1, 9), (2, 9)], [(21, 9), (22, 9)], [(2, 14), (3, 13)], [(21, 14), (20, 13)],
]

/// 24x24 pixel-art bulb; lv 0 (off) ... 10 (full)
func bulbSprite(_ lv: Int) -> CGImage {
    let t = Double(lv) / 10, cv = Canvas(24, 24), ox = 4, oy = 2
    let pal: [Character: CGColor] = [
        "O": C(24, 20, 40),
        "G": lerp((96, 96, 112), (252, 224, 56), t),
        "H": lerp((160, 160, 176), (255, 255, 220), t),
        "F": lerp((56, 56, 68), (255, 120, 24), t),
        "B": C(160, 164, 176),
        "D": C(88, 92, 108),
    ]
    if lv >= 5 {
        let glow = C(255, 236, 120, 70 + (lv - 5) * 37)
        for y in 0...13 { for x in 0..<16 where bulbRows[y][x] == "." {
            let touches = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { d in
                let nx = x + d.0, ny = y + d.1
                return nx >= 0 && nx < 16 && ny >= 0 && ny < 20 && bulbRows[ny][nx] == "O"
            }
            if touches { cv.px(glow, x + ox, y + oy) }
        } }
    }
    for y in 0..<20 { for x in 0..<16 { if let c = pal[bulbRows[y][x]] { cv.px(c, x + ox, y + oy) } } }
    let rc = lerp((200, 150, 0), (255, 232, 40), t)
    for i in 0..<Int((Double(lv) * 7 / 10).rounded()) { for p in rays[i] { cv.px(rc, p.0, p.1) } }
    return cv.image()
}

/// Nearest-neighbor scaled image, optionally on a dark rounded tile (used for the Dock / app icon)
func pixelImage(_ img: CGImage, size: CGFloat, crop: CGRect? = nil, tile: Bool = false) -> NSImage {
    let src = crop.flatMap { img.cropping(to: $0) } ?? img
    return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        guard let g = NSGraphicsContext.current?.cgContext else { return false }
        g.interpolationQuality = .none
        var inner = r
        if tile {
            let box = r.insetBy(dx: r.width * 0.09, dy: r.height * 0.09)
            g.addPath(CGPath(roundedRect: box, cornerWidth: r.width * 0.2, cornerHeight: r.width * 0.2, transform: nil))
            g.setFillColor(C(14, 14, 38)); g.fillPath()
            inner = r.insetBy(dx: r.width * 0.16, dy: r.height * 0.16)
        }
        g.draw(src, in: inner)
        return true
    }
}

// MARK: - 8-bit sounds

func squareWave(_ freqs: [Double], ms: Double) -> AVAudioPlayer? {
    let rate = 11025, per = Int(Double(rate) * ms / 1000), n = per * freqs.count
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n)); d.append(contentsOf: Array("WAVEfmt ".utf8))
    u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate)); u16(1); u16(8)
    d.append(contentsOf: Array("data".utf8)); u32(UInt32(n))
    for f in freqs {
        let half = Double(rate) / f / 2
        for i in 0..<per { d.append(Int(Double(i) / half) % 2 == 1 ? 104 : 152) }
    }
    let p = try? AVAudioPlayer(data: d)
    p?.prepareToPlay()
    return p
}

final class Sounds {
    let move = squareWave([1568], ms: 18)
    let ok = squareWave([988, 1319, 1976], ms: 70)
    let save = squareWave([784, 1175], ms: 60)
    let load = squareWave([1175, 1568], ms: 45)
    let cancel = squareWave([523, 392], ms: 70)
}

// MARK: - Window + pixel UI

final class PixelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PixelView: NSView {
    static let W = 240, H = 176
    unowned let app: AppDelegate
    let scale: CGFloat
    var val = 100, applied = 100
    var hover = "", drag = false, blink = true, pending = false
    var toastSlot = -1, toastUntil = Date.distantPast
    var lastBeep = Date.distantPast, scrollAcc: CGFloat = 0
    var frameImage: CGImage?
    var liveTimer: Timer?, animTimer: Timer?

    let font = NSFont(name: "AppleGothic", size: 12) ?? NSFont.systemFont(ofSize: 12)
    let cBg = C(14, 14, 38), cStar = C(90, 90, 150), cWhite = C(248, 248, 248), cBlack = C(0, 0, 0)
    let cDim = C(120, 120, 168), cYellow = C(252, 216, 64), cEmpty = C(44, 44, 70), cRed = C(228, 60, 88), cHot = C(60, 40, 0)
    let rects: [(String, [Int])] = [
        ("close", [222, 7, 12, 11]), ("sound", [10, 6, 34, 13]), ("bar", [28, 84, 184, 14]),
        ("slot0", [20, 108, 60, 16]), ("save0", [20, 127, 60, 13]),
        ("slot1", [90, 108, 60, 16]), ("save1", [90, 127, 60, 13]),
        ("slot2", [160, 108, 60, 16]), ("save2", [160, 127, 60, 13]),
        ("apply", [62, 150, 52, 15]), ("cancel", [126, 150, 52, 15]),
    ]
    let stars: [(Int, Int, Bool)] = (0..<28).map { _ in (Int.random(in: 2..<238), Int.random(in: 2..<174), Bool.random()) }
    let digits: [Character: String] = [
        "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111", "4": "101101111001001",
        "5": "111100111001111", "6": "111100111101111", "7": "111001001001001", "8": "111101111101111", "9": "111101111001111",
        "%": "101001010100101",
    ]

    init(app: AppDelegate, scale: CGFloat) {
        self.app = app; self.scale = scale
        super.init(frame: NSRect(x: 0, y: 0, width: CGFloat(PixelView.W) * scale, height: CGFloat(PixelView.H) * scale))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // ---- lifecycle ----
    func opened() {
        val = Brightness.builtIn() ?? app.settings.applied
        applied = val
        liveTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let s = self, s.pending else { return }
            s.pending = false; Brightness.set(s.val)
        }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.blink.toggle(); self?.render()
        }
        render()
    }
    func closing() {
        liveTimer?.invalidate(); animTimer?.invalidate()
        if val != applied { Brightness.set(applied) }
    }

    // ---- drawing ----
    func text(_ cv: Canvas, _ s: String, _ x: Int, _ y: Int, _ c: CGColor, center: Bool = false) {
        let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: c) ?? .white])
        let line = CTLineCreateWithAttributedString(attr)
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &asc, &desc, &lead))
        let x0 = center ? CGFloat(x) - (width / 2).rounded() : CGFloat(x)
        let g = cv.ctx
        g.saveGState()
        g.setShouldAntialias(false); g.setAllowsFontSmoothing(false); g.setShouldSmoothFonts(false)
        g.translateBy(x: x0, y: CGFloat(y) + asc.rounded()); g.scaleBy(x: 1, y: -1)
        g.textPosition = .zero
        CTLineDraw(line, g)
        g.restoreGState()
    }
    func box(_ cv: Canvas, _ r: [Int], _ border: CGColor, _ fill: CGColor) {
        cv.px(border, r[0] + 1, r[1], r[2] - 2, r[3]); cv.px(border, r[0], r[1] + 1, r[2], r[3] - 2)
        cv.px(fill, r[0] + 2, r[1] + 2, r[2] - 4, r[3] - 4)
    }
    func big(_ cv: Canvas, _ s: String, _ x: Int, _ y: Int, _ k: Int, _ c: CGColor) {
        var x = x
        for ch in s {
            if let m = digits[ch] {
                for (i, bit) in m.enumerated() where bit == "1" { cv.px(c, x + (i % 3) * k, y + (i / 3) * k, k, k) }
            }
            x += 4 * k
        }
    }
    func rect(_ key: String) -> [Int] { rects.first { $0.0 == key }!.1 }

    func render() {
        let cv = Canvas(PixelView.W, PixelView.H), s = app.settings
        cv.px(cBg, 0, 0, PixelView.W, PixelView.H)
        for st in stars where st.2 || blink { cv.px(cStar, st.0, st.1) }
        box(cv, [4, 4, 232, 168], cWhite, cBlack)
        text(cv, "MONITOR BRIGHTNESS", 120, 8, cYellow, center: true)
        text(cv, "x", 226, 7, hover == "close" ? cRed : cDim)
        text(cv, s.sound ? "♪ON" : "♪OFF", 12, 7, hover == "sound" ? cYellow : (s.sound ? cWhite : cDim))
        cv.px(cWhite, 8, 21, 224, 1)

        // bulb + big number, centered as one group
        let num = "\(val)%", nw = num.count * 20 - 5, gx = (240 - (48 + 14 + nw)) / 2
        cv.ctx.saveGState()   // canvas is flipped; flip back so the sprite isn't drawn upside-down
        cv.ctx.translateBy(x: CGFloat(gx), y: 26 + 48); cv.ctx.scaleBy(x: 1, y: -1)
        cv.ctx.draw(app.sprites[Int((Double(val) / 10).rounded())], in: CGRect(x: 0, y: 0, width: 48, height: 48))
        cv.ctx.restoreGState()
        big(cv, num, gx + 62, 38, 5, cWhite)

        // segmented bar
        box(cv, rect("bar"), (hover == "bar" || drag) ? cYellow : cWhite, cBlack)
        let filled = Int((Double(val) / 5).rounded(.up))
        for i in 0..<20 {
            cv.px(i < filled ? lerp((60, 80, 220), (252, 216, 64), Double(i) / 19) : cEmpty, 30 + i * 9, 86, 8, 10)
        }
        let cx = 30 + Int((Double(val) * 1.79).rounded())
        cv.px(cYellow, cx - 2, 78, 5, 1); cv.px(cYellow, cx - 1, 79, 3, 1); cv.px(cYellow, cx, 80, 1, 1)

        // save slots
        for i in 0..<3 {
            var r = rect("slot\(i)"); let p = s.presets[i]
            box(cv, r, (hover == "slot\(i)" && p != nil) ? cYellow : (p != nil ? cWhite : cDim), cBlack)
            text(cv, p.map { "\(i + 1)P \($0)%" } ?? "\(i + 1)P ---", r[0] + 30, r[1] + 2, p != nil ? cWhite : cDim, center: true)
            r = rect("save\(i)")
            let hot = hover == "save\(i)", toast = toastSlot == i && Date() < toastUntil
            box(cv, r, (hot || toast) ? cYellow : cDim, (hot || toast) ? cHot : cBlack)
            text(cv, toast ? "SAVED!" : "저장", r[0] + 30, r[1] + 1, (hot || toast) ? cYellow : cWhite, center: true)
        }

        // buttons
        for (k, label) in [("apply", "적용"), ("cancel", "취소")] {
            let r = rect(k), hot = hover == k
            box(cv, r, hot ? cYellow : cWhite, cBlack)
            text(cv, label, r[0] + 29, r[1] + 2, hot ? cYellow : cWhite, center: true)
            if hot && blink {
                cv.px(cYellow, r[0] + 6, r[1] + 4, 1, 7); cv.px(cYellow, r[0] + 7, r[1] + 5, 1, 5)
                cv.px(cYellow, r[0] + 8, r[1] + 6, 1, 3); cv.px(cYellow, r[0] + 9, r[1] + 7, 1, 1)
            }
        }
        frameImage = cv.image()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext, let img = frameImage else { return }
        g.interpolationQuality = .none
        g.draw(img, in: bounds)
    }

    // ---- actions ----
    func play(_ p: AVAudioPlayer?) { guard app.settings.sound, let p = p else { return }; p.currentTime = 0; p.play() }

    func setVal(_ v: Int, quiet: Bool = false) {
        let v = max(0, min(100, v)); guard v != val else { return }
        val = v; pending = true
        if !quiet && Date().timeIntervalSince(lastBeep) > 0.045 { play(app.sounds.move); lastBeep = Date() }
        if drag { pending = false; Brightness.set(v) }
        app.setLiveIcon(v)
        render()
    }
    func barVal(_ x: Int) -> Int { Int((Double(x - 30) / 1.79).rounded()) }
    func applyNow() {
        applied = val
        app.commit(val)
        play(app.sounds.ok)
        app.closeWindow()
    }
    func cancelNow() { play(app.sounds.cancel); app.closeWindow() }
    func load(_ i: Int) { if let p = app.settings.presets[i] { play(app.sounds.load); setVal(p, quiet: true) } }
    func save(_ i: Int) {
        app.settings.presets[i] = val; app.settings.save(); app.refreshMenus()
        play(app.sounds.save); toastSlot = i; toastUntil = Date().addingTimeInterval(0.9); render()
    }
    func toggleSound() { app.settings.sound.toggle(); app.settings.save(); play(app.sounds.load); render() }

    // ---- input ----
    func point(_ e: NSEvent) -> (Int, Int) {
        let p = convert(e.locationInWindow, from: nil)
        return (Int(p.x / scale), Int((bounds.height - p.y) / scale))
    }
    func hit(_ x: Int, _ y: Int) -> String {
        rects.first { r in x >= r.1[0] && x < r.1[0] + r.1[2] && y >= r.1[1] && y < r.1[1] + r.1[3] }?.0 ?? ""
    }
    override func mouseDown(with e: NSEvent) {
        let (x, y) = point(e), k = hit(x, y)
        switch k {
        case "bar": drag = true; setVal(barVal(x))
        case "apply": applyNow()
        case "cancel", "close": cancelNow()
        case "sound": toggleSound()
        case let s where s.hasPrefix("slot"): load(Int(String(s.last!))!)
        case let s where s.hasPrefix("save"): save(Int(String(s.last!))!)
        default: if y < 22 { window?.performDrag(with: e) }
        }
    }
    override func mouseDragged(with e: NSEvent) { if drag { setVal(barVal(point(e).0)) } }
    override func mouseUp(with e: NSEvent) { drag = false; render() }
    override func mouseMoved(with e: NSEvent) {
        let (x, y) = point(e), k = hit(x, y)
        if k != hover { hover = k; (k.isEmpty ? NSCursor.arrow : NSCursor.pointingHand).set(); render() }
    }
    override func scrollWheel(with e: NSEvent) {
        if e.hasPreciseScrollingDeltas {          // trackpad: 1% per few points of movement
            scrollAcc += e.scrollingDeltaY
            while abs(scrollAcc) >= 6 { setVal(val + (scrollAcc > 0 ? 1 : -1)); scrollAcc -= scrollAcc > 0 ? 6 : -6 }
        } else if e.scrollingDeltaY != 0 {        // mouse wheel: 5% per notch
            setVal(val + (e.scrollingDeltaY > 0 ? 5 : -5))
        }
    }
    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 123: setVal(val - 1)
        case 124: setVal(val + 1)
        case 125: setVal(val - 10)
        case 126: setVal(val + 10)
        case 36, 76: applyNow()
        case 53: cancelNow()
        default:
            switch e.charactersIgnoringModifiers?.lowercased() ?? "" {
            case "1": load(0)
            case "2": load(1)
            case "3": load(2)
            case "m": toggleSound()
            default: super.keyDown(with: e)
            }
        }
    }
}

// MARK: - App: Dock + menu bar

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    var settings = Settings.load()
    let sprites = (0...10).map(bulbSprite)
    let sounds = Sounds()
    var statusItem: NSStatusItem!
    var window: PixelWindow?
    var view: PixelView?
    var iconLevel = -1

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self
        statusItem.menu = menu

        // External monitors lose their gamma when the app quits, so restore the last level now
        let start = Brightness.builtIn() ?? settings.applied
        Brightness.set(start)
        updateIcons(start, persist: true)

        // Screens reset gamma after sleep or when plugged in; re-apply the saved level
        let reapply: (Notification) -> Void = { [weak self] _ in
            guard let s = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Brightness.set(s.view?.val ?? s.settings.applied) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reapply)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reapply)

        // Keep the icon in sync when brightness is changed with the keyboard keys
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let s = self, s.window == nil, let b = Brightness.builtIn() else { return }
            s.setLiveIcon(b)
        }
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { buildMenu(NSMenu(), full: false) }
    func menuNeedsUpdate(_ menu: NSMenu) { menu.removeAllItems(); _ = buildMenu(menu, full: true) }
    func refreshMenus() { /* menus are rebuilt each time they open */ }

    @discardableResult
    func buildMenu(_ m: NSMenu, full: Bool) -> NSMenu {
        for (i, p) in settings.presets.enumerated() {
            guard let p = p else { continue }
            let item = NSMenuItem(title: "\(i + 1)P  Brightness \(p)%", action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.target = self; item.tag = i
            item.image = pixelImage(sprites[Int((Double(p) / 10).rounded())], size: 18, crop: CGRect(x: 1, y: 0, width: 22, height: 22))
            m.addItem(item)
        }
        if full {
            if m.items.count > 0 { m.addItem(.separator()) }
            m.addItem(withTitle: "Open Monitor Brightness", action: #selector(openWindow), keyEquivalent: "").target = self
            let snd = m.addItem(withTitle: "Sound", action: #selector(toggleSound), keyEquivalent: "")
            snd.target = self; snd.state = settings.sound ? .on : .off
            if #available(macOS 13.0, *) {
                let login = m.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
                login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            }
            m.addItem(.separator())
            m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }
        return m
    }

    @objc func applyPreset(_ sender: NSMenuItem) {
        guard let p = settings.presets[sender.tag] else { return }
        if let v = view { v.setVal(p, quiet: true); v.applied = p }
        commit(p)
    }
    @objc func openWindow() { showWindow() }
    @objc func toggleSound() { settings.sound.toggle(); settings.save(); view?.render() }
    @objc func toggleLogin() {
        if #available(macOS 13.0, *) {
            let svc = SMAppService.mainApp
            if svc.status == .enabled { try? svc.unregister() } else { try? svc.register() }
        }
    }

    /// Final brightness: apply, remember, and update every icon (Dock, menu bar, Finder/Launchpad)
    func commit(_ p: Int) {
        Brightness.set(p)
        settings.applied = p; settings.save()
        updateIcons(p, persist: true)
    }
    func setLiveIcon(_ p: Int) { updateIcons(p, persist: false) }

    func updateIcons(_ p: Int, persist: Bool) {
        let lv = Int((Double(p) / 10).rounded())
        if lv != iconLevel {
            iconLevel = lv
            statusItem.button?.image = pixelImage(sprites[lv], size: 22, crop: CGRect(x: 1, y: 0, width: 22, height: 22))
            NSApp.applicationIconImage = pixelImage(sprites[lv], size: 512, tile: true)
        }
        if persist {   // icon shown by Finder / Launchpad when the app is not running
            NSWorkspace.shared.setIcon(pixelImage(sprites[lv], size: 512, tile: true), forFile: Bundle.main.bundlePath, options: [])
        }
    }

    func showWindow() {
        if window == nil {
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let scale: CGFloat = screen.visibleFrame.height < 700 ? 2 : 3
            let v = PixelView(app: self, scale: scale)
            let w = PixelWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = v; w.isOpaque = true; w.hasShadow = true; w.level = .floating
            w.title = "Monitor Brightness"; w.delegate = self; w.isReleasedWhenClosed = false
            let f = screen.frame   // exact center of the screen
            w.setFrameOrigin(NSPoint(x: f.midX - v.frame.width / 2, y: f.midY - v.frame.height / 2))
            window = w; view = v
            v.opened()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(view)
    }
    func closeWindow() {
        view?.closing()
        window?.orderOut(nil)
        window = nil; view = nil
        updateIcons(settings.applied, persist: false)
    }
}

// MARK: - main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
