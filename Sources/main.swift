import Cocoa
import ScreenCaptureKit
import CoreMedia
import ServiceManagement

// MARK: - Config

struct Config: Codable {
    var top = 0, right = 0, bottom = 0, left = 0
    var offset = 0
    var reversed = false
    var colorOrder = "RGB"
    var baud = 115200
    var port = ""            // leeg = automatisch
    var brightness = 1.0
    var saturation = 1.0
    var gamma = 1.8
    var smoothing = 0.2
    var depth = 0.12
    var enabled = true
    var boost = 1.5          // versterking vóór gamma
    var wbR = 1.0, wbG = 1.0, wbB = 1.0   // witbalans (1.0 = volle sterkte)
    var kind = "ambi"                      // off, ambi, static, anim
    var staticR = 1.0, staticG = 0.55, staticB = 0.15
    var anim = "Regenboog"
    var animSpeed = 1.0
    var ignoreBars = true
    var vivid = 0.6          // kleurintensiteit: kleuren optillen naar volle helderheid
    var antiFlicker = 0.6    // kleine/korte veranderingen afvlakken, scènewissels snel
    var followNightShift = true   // LEDs worden warmer als Night Shift actief is
    var nsAmount = 1.0            // hoeveel van het Night Shift-effect (0 = geen, 1 = zoals scherm)
    var blackLevel = 0.06    // zwartdrempel: vlakken donkerder dan dit -> LED uit
    var cfgVersion = 3

    init() {}

    enum CodingKeys: String, CodingKey {
        case top, right, bottom, left, offset, reversed, colorOrder, baud, port
        case brightness, saturation, gamma, smoothing, depth, enabled, boost, wbR, wbG, wbB
        case kind, staticR, staticG, staticB, anim, animSpeed, ignoreBars, vivid, antiFlicker, blackLevel, followNightShift, nsAmount, cfgVersion
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        top = try c.decodeIfPresent(Int.self, forKey: .top) ?? top
        right = try c.decodeIfPresent(Int.self, forKey: .right) ?? right
        bottom = try c.decodeIfPresent(Int.self, forKey: .bottom) ?? bottom
        left = try c.decodeIfPresent(Int.self, forKey: .left) ?? left
        offset = try c.decodeIfPresent(Int.self, forKey: .offset) ?? offset
        reversed = try c.decodeIfPresent(Bool.self, forKey: .reversed) ?? reversed
        colorOrder = try c.decodeIfPresent(String.self, forKey: .colorOrder) ?? colorOrder
        baud = try c.decodeIfPresent(Int.self, forKey: .baud) ?? baud
        port = try c.decodeIfPresent(String.self, forKey: .port) ?? port
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? saturation
        gamma = try c.decodeIfPresent(Double.self, forKey: .gamma) ?? gamma
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? smoothing
        depth = try c.decodeIfPresent(Double.self, forKey: .depth) ?? depth
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        boost = try c.decodeIfPresent(Double.self, forKey: .boost) ?? boost
        wbR = try c.decodeIfPresent(Double.self, forKey: .wbR) ?? wbR
        wbG = try c.decodeIfPresent(Double.self, forKey: .wbG) ?? wbG
        wbB = try c.decodeIfPresent(Double.self, forKey: .wbB) ?? wbB
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? kind
        staticR = try c.decodeIfPresent(Double.self, forKey: .staticR) ?? staticR
        staticG = try c.decodeIfPresent(Double.self, forKey: .staticG) ?? staticG
        staticB = try c.decodeIfPresent(Double.self, forKey: .staticB) ?? staticB
        anim = try c.decodeIfPresent(String.self, forKey: .anim) ?? anim
        animSpeed = try c.decodeIfPresent(Double.self, forKey: .animSpeed) ?? animSpeed
        ignoreBars = try c.decodeIfPresent(Bool.self, forKey: .ignoreBars) ?? ignoreBars
        cfgVersion = try c.decodeIfPresent(Int.self, forKey: .cfgVersion) ?? 1
        vivid = try c.decodeIfPresent(Double.self, forKey: .vivid) ?? vivid
        antiFlicker = try c.decodeIfPresent(Double.self, forKey: .antiFlicker) ?? antiFlicker
        blackLevel = try c.decodeIfPresent(Double.self, forKey: .blackLevel) ?? blackLevel
        followNightShift = try c.decodeIfPresent(Bool.self, forKey: .followNightShift) ?? followNightShift
        nsAmount = try c.decodeIfPresent(Double.self, forKey: .nsAmount) ?? nsAmount
        if cfgVersion < 2 { smoothing = min(smoothing, 0.2); cfgVersion = 2 }
        if cfgVersion < 3 {
            // nieuwe snelle firmware: GRB zit in de firmware, app stuurt RGB op 1 Mbaud
            baud = 1_000_000; colorOrder = "RGB"
            gamma = min(gamma, 1.3); saturation = max(saturation, 1.25)
            cfgVersion = 3
        }
    }

    var total: Int { top + right + bottom + left }

    static func load() -> Config {
        if let d = UserDefaults.standard.data(forKey: "config"),
           let c = try? JSONDecoder().decode(Config.self, from: d) { return c }
        return Config()
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "config") }
    }
}

// MARK: - Instellingen importeren/exporteren
// Hetzelfde JSON-bestand werkt op macOS en Windows. De seriële poort (en op Windows/macOS
// verschillende dingen zoals de poortnaam) worden niet overgenomen.

struct SettingsFile: Codable {
    var app = "Ambilight"
    var format = 1
    var settings: Config
}

enum SettingsIO {
    static func encode(_ c: Config) -> Data? {
        var c = c
        c.port = ""
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? e.encode(SettingsFile(settings: c))
    }

    static func decode(_ d: Data, keepingPortFrom cur: Config) -> Config? {
        guard let f = try? JSONDecoder().decode(SettingsFile.self, from: d), f.app == "Ambilight" else { return nil }
        var c = f.settings
        c.port = cur.port
        return c
    }

    static func export() {
        let p = NSSavePanel()
        p.title = "Ambilight-instellingen exporteren"
        p.nameFieldStringValue = "ambilight-instellingen.json"
        p.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url, let d = encode(Engine.shared.cfg) else { return }
        do { try d.write(to: url) } catch {
            let a = NSAlert(); a.messageText = "Exporteren mislukt"; a.informativeText = error.localizedDescription; a.runModal()
        }
    }

    static func importFile(then reload: () -> Void) {
        let p = NSOpenPanel()
        p.title = "Ambilight-instellingen importeren"
        p.allowedContentTypes = [.json]
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        guard let d = try? Data(contentsOf: url), let c = decode(d, keepingPortFrom: Engine.shared.cfg) else {
            let a = NSAlert(); a.messageText = "Dit is geen geldig Ambilight-instellingenbestand"; a.runModal(); return
        }
        Engine.shared.cfg = c
        Engine.shared.restoreMode()
        reload()
    }
}

// MARK: - Serial

final class Serial {
    var fd: Int32 = -1
    var path: String?
    var baud = 0

    func open(_ p: String, _ b: Int) -> Bool {
        close()
        let f = Darwin.open(p, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard f >= 0 else { return false }
        var t = termios()
        tcgetattr(f, &t)
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(b))
        t.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(PARENB | CSTOPB)
        tcsetattr(f, TCSANOW, &t)
        var spd = speed_t(b)
        _ = ioctl(f, 0x80085402 /* IOSSIOSPEED */, &spd)   // nodig voor o.a. 1.000.000 baud
        _ = fcntl(f, F_SETFL, 0) // blocking writes
        fd = f; path = p; baud = b
        return true
    }

    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1; path = nil
    }

    func write(_ data: [UInt8]) {
        guard fd >= 0 else { return }
        var sent = 0
        while sent < data.count {
            let r = data[sent...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if r <= 0 { close(); return }   // kabel eruit
            sent += r
        }
    }
}

func autoPort() -> String? {
    availablePorts().first
}

func availablePorts() -> [String] {
    let items = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
    return items.filter { $0.hasPrefix("cu.usbserial") || $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("cu.wchusbserial") }
        .sorted().map { "/dev/" + $0 }
}

// MARK: - Night Shift (leest de systeemstatus; geen schermopname nodig)

enum NightShift {
    typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    typealias GetStrength = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> Bool

    static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
    }()

    static func state() -> (active: Bool, strength: Float)? {
        guard let c = client else { return nil }
        let cls: AnyClass = type(of: c)
        let s1 = NSSelectorFromString("getBlueLightStatus:"), s2 = NSSelectorFromString("getStrength:")
        guard c.responds(to: s1) else { return nil }
        let f1 = unsafeBitCast(class_getMethodImplementation(cls, s1), to: GetStatus.self)
        var raw = [UInt8](repeating: 0, count: 64)
        guard raw.withUnsafeMutableBytes({ f1(c, s1, $0.baseAddress!) }) else { return nil }
        var st: Float = 1
        if c.responds(to: s2) {
            let f2 = unsafeBitCast(class_getMethodImplementation(cls, s2), to: GetStrength.self)
            _ = f2(c, s2, &st)
        }
        return (raw[0] != 0, max(0, min(1, st)))
    }

    static func rgb(_ kelvin: Double) -> [Double] {
        let t = kelvin / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        return [min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b))]
    }

    // Vermenigvuldigers voor R,G,B (1.0 = geen verandering)
    static func multipliers(amount: Double) -> [Float] {
        guard let s = state(), s.active else { return [1, 1, 1] }
        let kelvin = 6500 - 3800 * Double(s.strength) * max(0, min(1.5, amount))
        let w = rgb(6500), c = rgb(max(1900, kelvin))
        let m = (0..<3).map { c[$0] / max(1, w[$0]) }
        let top = max(m[0], m[1], m[2])
        return m.map { Float($0 / top) }
    }
}

// MARK: - Layout

func perimeterIndex(_ i: Int, _ n: Int, _ c: Config) -> Int {
    let step = c.reversed ? -i : i
    return (((c.offset + step) % n) + n) % n
}

func locate(_ p: Int, _ c: Config) -> (side: Int, k: Int, cnt: Int) {
    let counts = [c.top, c.right, c.bottom, c.left]
    var q = p
    for s in 0..<4 {
        if q < counts[s] { return (s, q, counts[s]) }
        q -= counts[s]
    }
    return (0, 0, max(1, c.top))
}

// MARK: - Engine

enum Mode: Equatable {
    case off, ambi, sides, chase, white, staticColor, anim
    case single(Int)
}

let animNames = ["Regenboog", "Kleurwissel", "Ademen", "Looplicht", "Vuur"]
let kindNames = ["off", "ambi", "static", "anim"]

func hsv(_ h: Double, _ s: Double = 1, _ v: Double = 1) -> [Float] {
    let hh = (h - floor(h)) * 6
    let i = Int(hh), f = hh - Double(i)
    let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
    let r: (Double, Double, Double)
    switch i % 6 {
    case 0: r = (v, t, p)
    case 1: r = (q, v, p)
    case 2: r = (p, v, t)
    case 3: r = (p, q, v)
    case 4: r = (t, p, v)
    default: r = (v, p, q)
    }
    return [Float(r.0 * 255), Float(r.1 * 255), Float(r.2 * 255)]
}

func animate(_ des: inout [Float], _ n: Int, _ c: Config, _ t: Double) {
    let sp = c.animSpeed
    let base: [Float] = [Float(c.staticR * 255), Float(c.staticG * 255), Float(c.staticB * 255)]
    func put(_ i: Int, _ col: [Float], _ f: Float = 1) {
        des[3 * i] = col[0] * f; des[3 * i + 1] = col[1] * f; des[3 * i + 2] = col[2] * f
    }
    switch c.anim {
    case "Regenboog":
        for i in 0..<n { put(i, hsv(Double(perimeterIndex(i, n, c)) / Double(n) + t * 0.08 * sp)) }
    case "Kleurwissel":
        let col = hsv(t * 0.05 * sp)
        for i in 0..<n { put(i, col) }
    case "Ademen":
        let f = Float(0.5 + 0.5 * sin(t * sp * 1.5 - .pi / 2))
        for i in 0..<n { put(i, base, 0.04 + 0.96 * f * f) }
    case "Looplicht":
        let head = t * sp * 20
        let tail = max(4.0, Double(n) * 0.2)
        for i in 0..<n {
            let p = Double(perimeterIndex(i, n, c))
            var d = (head - p).truncatingRemainder(dividingBy: Double(n))
            if d < 0 { d += Double(n) }
            if d < tail { put(i, base, Float(1 - d / tail)) }
        }
    default: // Vuur
        for i in 0..<n {
            let a = sin(t * sp * (3 + Double(i % 5)) + Double(i) * 1.7)
            let b = sin(t * sp * 7.3 + Double(i) * 0.9)
            let f = Float(max(0, min(1, 0.55 + 0.3 * a + 0.15 * b)))
            put(i, [255, 60 + 110 * f, 0], 0.25 + 0.75 * f)
        }
    }
}

final class Engine {
    static let shared = Engine()

    let q = DispatchQueue(label: "engine")
    let lock = NSLock()
    private var _cfg = Config.load()
    private var _mode: Mode = .ambi
    var status = "Starten…"            // schermopname-melding
    var arduinoStatus = "Zoeken…"
    private var _frames = 0
    var frames: Int { lock.lock(); defer { lock.unlock() }; return _frames }
    func bumpFrames() { lock.lock(); _frames += 1; lock.unlock() }
    func resetFrames() { lock.lock(); _frames = 0; lock.unlock() }

    func modeFromConfig() -> Mode {
        switch cfg.kind {
        case "off": return .off
        case "static": return .staticColor
        case "anim": return .anim
        default: return .ambi
        }
    }

    // (tekst, kleur) voor de schermopname-status
    func captureStatus() -> (String, NSColor) {
        if cfg.kind != "ambi" && mode != .ambi { return ("Niet nodig in deze modus", .secondaryLabelColor) }
        if !CGPreflightScreenCaptureAccess() {
            return ("UIT: geen toestemming. Zet Ambilight aan bij Schermopname", .systemRed)
        }
        if frames > 0 { return ("AAN: beeld wordt ontvangen", .systemGreen) }
        return ("Toestemming OK, wacht op beeld… (\(status))", .systemOrange)
    }

    func retryCapture() {
        DispatchQueue.main.async {
            self.capturing = false
            self.enqueue { [weak self] in await self?.capturer.stop() }
            self.resetFrames()
            self.updateCapture()
        }
    }
    private var _disp: [UInt8] = []
    func displayColors() -> [UInt8] { lock.lock(); defer { lock.unlock() }; return _disp }

    var cfg: Config {
        get { lock.lock(); defer { lock.unlock() }; return _cfg }
        set { lock.lock(); _cfg = newValue; lock.unlock(); newValue.save() }
    }
    var mode: Mode {
        get { lock.lock(); defer { lock.unlock() }; return _mode }
        set { lock.lock(); _mode = newValue; lock.unlock() }
    }

    // engine-queue state
    let serial = Serial()
    private var _target: [Float] = []
    func setTarget(_ t: [Float]) { lock.lock(); _target = t; lock.unlock() }
    func getTarget() -> [Float] { lock.lock(); defer { lock.unlock() }; return _target }
    var barHist = [[Int]](repeating: [], count: 4)   // alleen capture-queue
    var sentFrames = 0
    var cur: [Float] = []
    var held: [Float] = []   // vastgehouden doelkleur (dode zone tegen ruis)
    var nsMul: [Float] = [1, 1, 1]
    var nsTarget: [Float] = [1, 1, 1]
    var nsPoll = Date.distantPast
    var openedAt = Date.distantPast
    var lastTry = Date.distantPast
    var timer: DispatchSourceTimer?
    let t0 = Date()

    // capture
    let capturer = Capturer()
    var capturing = false
    var recheckScheduled = false
    var chain: Task<Void, Never>?

    func start() {
        capturer.onFrame = { [weak self] base, w, h, bpr in self?.process(base, w, h, bpr) }
        capturer.onStopped = { [weak self] msg in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.capturing = false
                self.status = msg
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.updateCapture() }
            }
        }
        let th = Thread { [weak self] in self?.outputLoop() }
        th.qualityOfService = .userInteractive
        th.name = "ambilight-output"
        th.start()
        updateCapture()
    }

    func setMode(_ m: Mode) {
        mode = m
        DispatchQueue.main.async { self.updateCapture() }
    }

    func restoreMode() { setMode(modeFromConfig()) }

    func enqueue(_ op: @escaping () async -> Void) {
        let prev = chain
        chain = Task { await prev?.value; await op() }
    }

    func updateCapture() {
        let want = mode == .ambi
        if want && !capturing {
            // Zonder toestemming NIET proberen: elke poging toont anders weer de macOS-vraag.
            if !CGPreflightScreenCaptureAccess() {
                status = "Wacht op toestemming voor schermopname"
                if !recheckScheduled {
                    recheckScheduled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        self?.recheckScheduled = false
                        self?.updateCapture()
                    }
                }
                return
            }
            capturing = true
            resetFrames()
            enqueue { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.capturer.start()
                    self.status = "Actief"
                } catch {
                    self.status = "Schermopname mislukt (toestemming?)"
                    DispatchQueue.main.async {
                        self.capturing = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.updateCapture() }
                    }
                }
            }
        } else if !want && capturing {
            capturing = false
            enqueue { [weak self] in await self?.capturer.stop() }
        }
    }

    // Draait op de capture-queue: gemiddelde kleur per LED-zone.
    func process(_ base: UnsafePointer<UInt8>, _ w: Int, _ h: Int, _ bpr: Int) {
        let c = cfg
        let n = c.total
        guard n > 0 else { return }
        var ox = 0, oy = 0, cw = w, ch = h
        if c.ignoreBars {
            func dark(_ px: UnsafePointer<UInt8>) -> Bool { max(px[0], px[1], px[2]) <= 24 }
            func rowDark(_ y: Int) -> Bool {
                var x = 0
                while x < w { if !dark(base + y * bpr + x * 4) { return false }; x += 3 }
                return true
            }
            func colDark(_ x: Int) -> Bool {
                var y = 0
                while y < h { if !dark(base + y * bpr + x * 4) { return false }; y += 3 }
                return true
            }
            var t = 0, b = 0, l = 0, r = 0
            while t < h / 3 && rowDark(t) { t += 1 }
            while b < h / 3 && rowDark(h - 1 - b) { b += 1 }
            while l < w / 3 && colDark(l) { l += 1 }
            while r < w / 3 && colDark(w - 1 - r) { r += 1 }
            // Helemaal zwart beeld: niets leren, vorige balken houden.
            if !(t >= h / 3 && b >= h / 3) {
                for (i, v) in [t, b, l, r].enumerated() {
                    barHist[i].append(v)
                    if barHist[i].count > 90 { barHist[i].removeFirst() }
                }
            }
            let bars = barHist.map { ($0.min() ?? 0) >= 2 ? ($0.min() ?? 0) : 0 }
            oy = bars[0]; ch = max(8, h - bars[0] - bars[1])
            ox = bars[2]; cw = max(8, w - bars[2] - bars[3])
        }
        let d = max(1, Int(c.depth * Double(ch)))
        var out = [Float](repeating: 0, count: 3 * n)
        for p in 0..<n {
            let (s, k, cnt) = locate(p, c)
            var x0 = 0, x1 = 0, y0 = 0, y1 = 0
            switch s {
            case 0: x0 = ox + k * cw / cnt; x1 = ox + (k + 1) * cw / cnt; y0 = oy; y1 = oy + d
            case 1: x0 = ox + cw - d; x1 = ox + cw; y0 = oy + k * ch / cnt; y1 = oy + (k + 1) * ch / cnt
            case 2: x0 = ox + cw - (k + 1) * cw / cnt; x1 = ox + cw - k * cw / cnt; y0 = oy + ch - d; y1 = oy + ch
            default: x0 = ox; x1 = ox + d; y0 = oy + ch - (k + 1) * ch / cnt; y1 = oy + ch - k * ch / cnt
            }
            x0 = max(0, min(w - 1, x0)); y0 = max(0, min(h - 1, y0))
            x1 = max(x0 + 1, min(w, x1)); y1 = max(y0 + 1, min(h, y1))
            var sr = 0, sg = 0, sb = 0
            for y in y0..<y1 {
                var px = base + y * bpr + x0 * 4
                for _ in x0..<x1 {
                    sb += Int(px[0]); sg += Int(px[1]); sr += Int(px[2])
                    px += 4
                }
            }
            let cntPx = Float((x1 - x0) * (y1 - y0))
            out[3 * p] = Float(sr) / cntPx
            out[3 * p + 1] = Float(sg) / cntPx
            out[3 * p + 2] = Float(sb) / cntPx
        }
        bumpFrames()
        setTarget(out)
    }

    // Eigen thread: stuurt zo snel als de seriële lijn toelaat, maar nooit sneller.
    // Daardoor loopt de USB-buffer nooit vol en is er geen opgebouwde vertraging.
    func outputLoop() {
        var last = Date()
        var fpsStart = Date()
        while true {
            let now = Date()
            let dt = min(0.2, now.timeIntervalSince(last))
            last = now
            let bytes = tick(dt)
            if bytes > 0 && serial.fd >= 0 {
                tcdrain(serial.fd)       // wacht tot het frame echt verstuurd is
                sentFrames += 1
            }
            let baud = Double(max(9600, serial.baud))
            let minInterval = bytes > 0 ? max(1.0 / 60, Double(bytes) * 10 / baud * 1.03) : 0.05
            let el = Date().timeIntervalSince(now)
            if el < minInterval { Thread.sleep(forTimeInterval: minInterval - el) }
            if Date().timeIntervalSince(fpsStart) >= 1 {
                if serial.fd >= 0, let p = serial.path, sentFrames > 0 || mode == .off {
                    arduinoStatus = "Verbonden (\((p as NSString).lastPathComponent)) · \(sentFrames) fps"
                }
                sentFrames = 0
                fpsStart = Date()
            }
        }
    }

    func tick(_ dt: Double) -> Int {
        let c = cfg
        let n = c.total
        guard n > 0 else { arduinoStatus = "Stel eerst je LEDs in"; return 0 }
        let now = Date()
        let want = c.port.isEmpty ? autoPort() : c.port

        if serial.fd >= 0 && (serial.path != want || serial.baud != c.baud) { serial.close(); lastTry = .distantPast }
        if serial.fd < 0 {
            if now.timeIntervalSince(lastTry) < 2 { return 0 }
            lastTry = now
            guard let p = want, serial.open(p, c.baud) else {
                arduinoStatus = "Geen Arduino gevonden"; return 0
            }
            openedAt = now
            arduinoStatus = "Verbonden (" + p + ")"
        }
        if now.timeIntervalSince(openedAt) < 2.5 { return 0 } // Arduino herstart bij openen

        let m = mode
        var des = [Float](repeating: 0, count: 3 * n)
        let t = Date().timeIntervalSince(t0)
        switch m {
        case .off: break
        case .ambi:
            let tp = getTarget()
            if tp.count == 3 * n {
                for i in 0..<n {
                    let p = perimeterIndex(i, n, c)
                    des[3 * i] = tp[3 * p]; des[3 * i + 1] = tp[3 * p + 1]; des[3 * i + 2] = tp[3 * p + 2]
                }
            }
        case .sides:
            let cols: [[Float]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 200, 0]]
            for i in 0..<n {
                let s = locate(perimeterIndex(i, n, c), c).side
                let col = i == 0 ? [255, 255, 255] : cols[s]
                des[3 * i] = col[0]; des[3 * i + 1] = col[1]; des[3 * i + 2] = col[2]
            }
        case .staticColor:
            for i in 0..<n {
                des[3 * i] = Float(c.staticR * 255); des[3 * i + 1] = Float(c.staticG * 255); des[3 * i + 2] = Float(c.staticB * 255)
            }
        case .anim:
            animate(&des, n, c, t)
        case .chase:
            let i = Int(t * 12) % n
            des[3 * i] = 255; des[3 * i + 1] = 255; des[3 * i + 2] = 255
        case .white:
            for k in 0..<(3 * n) { des[k] = 255 }
        case .single(let k):
            if k >= 0 && k < n { des[3 * k] = 255; des[3 * k + 1] = 255; des[3 * k + 2] = 255 }
        }

        if cur.count != 3 * n { cur = [Float](repeating: 0, count: 3 * n) }
        if m != .ambi { held = [] }
        if m == .ambi {
            // Dode zone: schermopname heeft ruis (video-compressie, dithering, cursor).
            // Een LED volgt pas als het doel echt verschilt van wat hij nu toont.
            if held.count != 3 * n { held = des }
            let thr = Float(3 + 6 * c.antiFlicker)
            for i in 0..<n {
                let b = 3 * i
                let diff = max(abs(des[b] - held[b]), abs(des[b + 1] - held[b + 1]), abs(des[b + 2] - held[b + 2]))
                let dark = max(des[b], des[b + 1], des[b + 2]) < 3
                if diff > thr || (dark && diff > 0) {
                    held[b] = des[b]; held[b + 1] = des[b + 1]; held[b + 2] = des[b + 2]
                }
            }
            des = held
            // tijd-gebaseerd: 0 = direct, 0.95 ≈ halve seconde naijlen
            // + anti-flikker: kleine verschillen (tekst, cursor, menuutjes) langzaam,
            //   grote verschillen (scènewissel) snel.
            let tauFast = c.smoothing * c.smoothing * 0.6
            let af = c.antiFlicker
            for i in 0..<n {
                let b = 3 * i
                let diff = max(abs(des[b] - cur[b]), abs(des[b + 1] - cur[b + 1]), abs(des[b + 2] - cur[b + 2])) / 255
                var w = Double(min(1, max(0, (diff - 0.12) / 0.3)))      // 0 = klein, 1 = groot
                // relatief verschil telt ook: van 30 naar 5 is voor het oog een grote stap
                let curL = max(cur[b], cur[b + 1], cur[b + 2])
                let desL = max(des[b], des[b + 1], des[b + 2])
                let rel = abs(desL - curL) / max(curL, desL, 20)
                w = max(w, Double(min(1, max(0, (rel - 0.25) / 0.35))))
                if desL < curL * 0.6 { w = 1 }                           // donker worden: altijd direct
                let tau = (w >= 1 && desL < curL) ? tauFast * 0.5 : tauFast + af * (0.35 * (1 - w) + 0.06 * w)
                let a = tau < 0.002 ? Float(1) : Float(1 - exp(-dt / tau))
                for j in 0..<3 { cur[b + j] += (des[b + j] - cur[b + j]) * a }
            }
        } else {
            cur = des
        }

        let order = c.colorOrder.map { ch -> Int in ch == "R" ? 0 : (ch == "G" ? 1 : 2) }
        var buf = [UInt8](repeating: 0, count: 6 + 3 * n)
        let hi = UInt8(((n - 1) >> 8) & 0xFF), lo = UInt8((n - 1) & 0xFF)
        buf[0] = 0x41; buf[1] = 0x64; buf[2] = 0x61
        buf[3] = hi; buf[4] = lo; buf[5] = hi ^ lo ^ 0x55
        let sat = Float(c.saturation), gam = Float(c.gamma), br = Float(c.brightness)
        let boost = m == .ambi ? Float(c.boost) : 1
        let vivid = Float(c.vivid)
        let blackLvl = Float(c.blackLevel)
        if now.timeIntervalSince(nsPoll) > 1 {
            nsPoll = now
            nsTarget = c.followNightShift ? NightShift.multipliers(amount: c.nsAmount) : [1, 1, 1]
        }
        let nk = Float(1 - exp(-dt / 2.5))      // Night Shift fade ook rustig
        for j in 0..<3 { nsMul[j] += (nsTarget[j] - nsMul[j]) * nk }
        let nsm: [Float] = m == .ambi ? nsMul : [1, 1, 1]
        let wb: [Float] = [Float(c.wbR) * nsm[0], Float(c.wbG) * nsm[1], Float(c.wbB) * nsm[2]]
        var disp = [UInt8](repeating: 0, count: 3 * n)
        for i in 0..<n {
            var rgb = [cur[3 * i], cur[3 * i + 1], cur[3 * i + 2]]
            let g = 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]
            var lin: [Float] = [0, 0, 0]
            for j in 0..<3 {
                let v = g + (rgb[j] - g) * sat
                lin[j] = max(0, v) / 255
            }
            // Versterking met behoud van tint: alle kanalen met dezelfde factor,
            // nooit verder dan tot het felste kanaal op 100% staat.
            var mx0 = max(lin[0], lin[1], lin[2])
            if m == .ambi && blackLvl > 0 {
                // Zwartdrempel: te weinig licht in het vlak -> uit, met zachte overgang
                // tussen drempel en 2× drempel (geen harde aan/uit-flits).
                let f = min(1, max(0, (mx0 - blackLvl) / blackLvl))
                for j in 0..<3 { lin[j] *= f }
                mx0 *= f
            }
            if mx0 > 0 {
                let k = min(boost, 1 / mx0)
                for j in 0..<3 { lin[j] *= k }
            }
            if m == .ambi && vivid > 0 {
                // Til de kleur op richting volle helderheid, tint blijft gelijk.
                // Bijna-zwart wordt niet opgetild (anders gaat ruis gloeien).
                let mx = max(lin[0], lin[1], lin[2])
                if mx > 0.05 {
                    // alleen echte kleurvlakken optillen, niet de restjes van bijna-zwart
                    let ramp = min(1, (mx - 0.05) / 0.25)
                    let target = mx + (1 - mx) * vivid * ramp
                    let k = target / mx
                    for j in 0..<3 { lin[j] = min(1, lin[j] * k) }
                }
            }
            for j in 0..<3 {
                rgb[j] = min(255, powf(lin[j], gam) * br * 255 * wb[j])
                disp[3 * i + j] = UInt8(max(0, rgb[j] + 0.5))
            }
            for j in 0..<3 { buf[6 + 3 * i + j] = UInt8(max(0, min(255, rgb[order[j]] + 0.5))) }
        }
        lock.lock(); _disp = disp; lock.unlock()
        serial.write(buf)
        return buf.count
    }

    func shutdown() {
        mode = .off
        Thread.sleep(forTimeInterval: 0.25)   // output-thread stuurt nog een zwart frame
    }
}

// MARK: - Screen capture

final class Capturer: NSObject, SCStreamOutput, SCStreamDelegate {
    var stream: SCStream?
    var onFrame: ((UnsafePointer<UInt8>, Int, Int, Int) -> Void)?
    var onStopped: ((String) -> Void)?
    let queue = DispatchQueue(label: "capture")

    func start() async throws {
        if stream != nil { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let main = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == main }) ?? content.displays.first else {
            throw NSError(domain: "ambi", code: 1)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = 256
        cfg.height = max(16, 256 * display.height / max(1, display.width))
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.showsCursor = false
        cfg.queueDepth = 3
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stop() async {
        guard let s = stream else { return }
        stream = nil
        try? await s.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid else { return }
        guard let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let st = atts.first?[.status] as? Int, st == SCFrameStatus.complete.rawValue,
              let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        onFrame?(base.assumingMemoryBound(to: UInt8.self),
                 CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), CVPixelBufferGetBytesPerRow(pb))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        onStopped?("Schermopname gestopt, opnieuw proberen…")
    }
}

// MARK: - UI helpers

final class Act: NSObject {
    let f: (NSControl) -> Void
    init(_ f: @escaping (NSControl) -> Void) { self.f = f }
    @objc func go(_ s: Any?) { if let c = s as? NSControl { f(c) } }
}

final class SetupController: NSObject, NSWindowDelegate {
    var window: NSWindow!
    var acts: [Act] = []
    let eng = Engine.shared
    let totalLabel = NSTextField(labelWithString: "")
    let singleLabel = NSTextField(labelWithString: "0")
    var singleSlider: NSSlider!
    var mapWindow: NSWindow?
    var mapTimer: Timer?
    let offsetLabel = NSTextField(labelWithString: "")
    var screenLabel = NSTextField(labelWithString: "")
    var arduinoLabel = NSTextField(labelWithString: "")
    var mapStatus = NSTextField(labelWithString: "")
    var setupTimer: Timer?
    var wbSwatch: NSView!
    var wbInfo: NSTextField!

    func bind<T: NSControl>(_ c: T, _ f: @escaping (T) -> Void) -> T {
        let a = Act { f($0 as! T) }
        acts.append(a)
        c.target = a
        c.action = #selector(Act.go(_:))
        return c
    }

    func update(_ f: (inout Config) -> Void) {
        var c = eng.cfg
        f(&c)
        eng.cfg = c
    }

    func updateTotal() {
        let n = eng.cfg.total
        totalLabel.stringValue = "Totaal: \(n) LEDs  (moet gelijk zijn aan het aantal in je Arduino-firmware)"
        singleSlider?.maxValue = Double(max(1, n - 1))
    }

    func intRow(_ title: String, _ kp: WritableKeyPath<Config, Int>, max: Int = 999) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let val = NSTextField(labelWithString: "\(eng.cfg[keyPath: kp])")
        val.alignment = .right
        val.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let st = NSStepper()
        st.minValue = 0; st.maxValue = Double(max); st.increment = 1; st.valueWraps = false
        st.integerValue = eng.cfg[keyPath: kp]
        _ = bind(st) { [unowned self] s in
            self.update { $0[keyPath: kp] = s.integerValue }
            val.stringValue = "\(s.integerValue)"
            self.updateTotal()
        }
        return NSStackView(views: [lbl, val, st])
    }

    func sliderRow(_ title: String, _ kp: WritableKeyPath<Config, Double>, _ lo: Double, _ hi: Double) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let val = NSTextField(labelWithString: String(format: "%.2f", eng.cfg[keyPath: kp]))
        val.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let sl = NSSlider(value: eng.cfg[keyPath: kp], minValue: lo, maxValue: hi, target: nil, action: nil)
        sl.widthAnchor.constraint(equalToConstant: 220).isActive = true
        _ = bind(sl) { [unowned self] s in
            self.update { $0[keyPath: kp] = s.doubleValue }
            val.stringValue = String(format: "%.2f", s.doubleValue)
        }
        return NSStackView(views: [lbl, sl, val])
    }

    func popupRow(_ title: String, _ items: [String], selected: String, _ onChange: @escaping (String) -> Void) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: items)
        pop.selectItem(withTitle: selected)
        _ = bind(pop) { p in onChange(p.titleOfSelectedItem ?? "") }
        return NSStackView(views: [lbl, pop])
    }

    func header(_ s: String) -> NSView {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 13)
        return l
    }

    func button(_ title: String, _ f: @escaping () -> Void) -> NSButton {
        bind(NSButton(title: title, target: nil, action: nil)) { _ in f() }
    }

    func show() {
        if window != nil { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let c = eng.cfg
        stack.addArrangedSubview(header("Modus"))
        let seg = NSSegmentedControl(labels: ["Uit", "Ambilight", "Statisch", "Animatie"], trackingMode: .selectOne, target: nil, action: nil)
        seg.selectedSegment = max(0, kindNames.firstIndex(of: c.kind) ?? 1)
        _ = bind(seg) { [unowned self] s in
            self.update { $0.kind = kindNames[s.selectedSegment] }
            self.eng.restoreMode()
        }
        stack.addArrangedSubview(seg)
        let cw = NSColorWell()
        cw.color = NSColor(srgbRed: c.staticR, green: c.staticG, blue: c.staticB, alpha: 1)
        cw.widthAnchor.constraint(equalToConstant: 50).isActive = true
        cw.heightAnchor.constraint(equalToConstant: 24).isActive = true
        _ = bind(cw) { [unowned self] w in
            let col = w.color.usingColorSpace(.sRGB) ?? w.color
            self.update { $0.staticR = Double(col.redComponent); $0.staticG = Double(col.greenComponent); $0.staticB = Double(col.blueComponent) }
        }
        let cwl = NSTextField(labelWithString: "Kleur (statisch, ademen, looplicht)")
        cwl.widthAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(NSStackView(views: [cwl, cw]))
        stack.addArrangedSubview(popupRow("Animatie", animNames, selected: c.anim) { [unowned self] v in
            self.update { $0.anim = v }
        })
        stack.addArrangedSubview(sliderRow("Animatiesnelheid", \.animSpeed, 0.2, 3))

        stack.addArrangedSubview(header("Status"))
        stack.addArrangedSubview(screenLabel)
        stack.addArrangedSubview(arduinoLabel)
        stack.addArrangedSubview(NSStackView(views: [
            button("Schermopname-instellingen openen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            },
            button("Schermopname opnieuw proberen") { [unowned self] in self.eng.retryCapture() },
        ]))
        stack.addArrangedSubview(header("1. Aantal LEDs per zijde (kijk naar de voorkant van de tv)"))
        stack.addArrangedSubview(intRow("Boven", \.top))
        stack.addArrangedSubview(intRow("Rechts", \.right))
        stack.addArrangedSubview(intRow("Onder", \.bottom))
        stack.addArrangedSubview(intRow("Links", \.left))
        stack.addArrangedSubview(totalLabel)

        stack.addArrangedSubview(header("2. Positie en test"))
        stack.addArrangedSubview(NSStackView(views: [
            button("Schermvlakken tonen (zoals Prismatik)…") { [unowned self] in self.showZones() },
            button("LED-indicatie…") { [unowned self] in self.showMap() },
        ]))

        stack.addArrangedSubview(header("Instellingen delen (macOS ↔ Windows)"))
        stack.addArrangedSubview(NSStackView(views: [
            button("Exporteren…") { SettingsIO.export() },
            button("Importeren…") { [unowned self] in
                SettingsIO.importFile {
                    self.window.close()
                    DispatchQueue.main.async { self.show() }
                }
            },
        ]))

        stack.addArrangedSubview(header("4. Hardware"))
        stack.addArrangedSubview(popupRow("Kleurvolgorde", ["RGB", "RBG", "GRB", "GBR", "BRG", "BGR"], selected: c.colorOrder) { [unowned self] v in
            self.update { $0.colorOrder = v }
        })
        let ports = ["Automatisch"] + availablePorts()
        stack.addArrangedSubview(popupRow("Poort", ports, selected: c.port.isEmpty ? "Automatisch" : c.port) { [unowned self] v in
            self.update { $0.port = (v == "Automatisch") ? "" : v }
        })
        stack.addArrangedSubview(popupRow("Baudrate", ["115200", "250000", "500000", "1000000"], selected: "\(c.baud)") { [unowned self] v in
            self.update { $0.baud = Int(v) ?? 115200 }
        })

        stack.addArrangedSubview(header("3. Beeld"))
        stack.addArrangedSubview(sliderRow("Helderheid", \.brightness, 0, 1))
        stack.addArrangedSubview(sliderRow("Kleurintensiteit", \.vivid, 0, 1))
        stack.addArrangedSubview(sliderRow("Versterking (donkere beelden)", \.boost, 1, 4))
        stack.addArrangedSubview(sliderRow("Verzadiging", \.saturation, 0, 2))
        stack.addArrangedSubview(sliderRow("Gamma (lager = lichter)", \.gamma, 1, 3))
        stack.addArrangedSubview(sliderRow("Vloeiendheid (0 = direct)", \.smoothing, 0, 0.95))
        stack.addArrangedSubview(sliderRow("Anti-flikker", \.antiFlicker, 0, 1))
        stack.addArrangedSubview(sliderRow("Zwartdrempel (min. licht in vlak)", \.blackLevel, 0, 0.3))
        let nsb = bind(NSButton(checkboxWithTitle: "Night Shift volgen (LEDs worden warmer met je scherm)", target: nil, action: nil)) { [unowned self] b in
            self.update { $0.followNightShift = (b.state == .on) }
        }
        nsb.state = c.followNightShift ? .on : .off
        stack.addArrangedSubview(nsb)
        stack.addArrangedSubview(sliderRow("Night Shift-sterkte", \.nsAmount, 0, 1.5))
        stack.addArrangedSubview(sliderRow("Randdiepte", \.depth, 0.03, 0.4))
        let bars = bind(NSButton(checkboxWithTitle: "Zwarte balken negeren (films)", target: nil, action: nil)) { [unowned self] b in
            self.update { $0.ignoreBars = (b.state == .on) }
        }
        bars.state = c.ignoreBars ? .on : .off
        stack.addArrangedSubview(bars)
        stack.addArrangedSubview(whiteBalanceSection())

        updateTotal()
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ambilight instellingen"
        window.contentView = stack
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshStatus()
        setupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshStatus() }
    }

    func dotted(_ text: String, _ color: NSColor) -> NSAttributedString {
        let r = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: color])
        r.append(NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.labelColor]))
        return r
    }

    func refreshStatus() {
        let (t, col) = eng.captureStatus()
        screenLabel.attributedStringValue = dotted("Schermopname: " + t, col)
        let ok = eng.arduinoStatus.hasPrefix("Verbonden")
        arduinoLabel.attributedStringValue = dotted("Arduino: " + eng.arduinoStatus, ok ? .systemGreen : .systemOrange)
        mapStatus.attributedStringValue = dotted("Schermopname: " + t, col)
    }

    // MARK: witbalans

    func whiteBalanceSection() -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 8
        box.addArrangedSubview(header("5. Witbalans"))
        let hint = NSTextField(wrappingLabelWithString: "Tijdens het schuiven branden alle LEDs wit. Verlaag het kanaal dat te sterk is (bijv. blauw bij een te koel/blauw wit) tot het wit er echt wit uitziet. Rechts zie je een voorbeeld.")
        hint.widthAnchor.constraint(equalToConstant: 460).isActive = true
        hint.textColor = .secondaryLabelColor
        box.addArrangedSubview(hint)

        wbSwatch = NSView()
        wbSwatch.wantsLayer = true
        wbSwatch.layer?.cornerRadius = 6
        wbSwatch.widthAnchor.constraint(equalToConstant: 70).isActive = true
        wbSwatch.heightAnchor.constraint(equalToConstant: 50).isActive = true
        let ref = NSView()
        ref.wantsLayer = true
        ref.layer?.cornerRadius = 6
        ref.layer?.backgroundColor = NSColor.white.cgColor
        ref.layer?.borderWidth = 1
        ref.layer?.borderColor = NSColor.separatorColor.cgColor
        ref.widthAnchor.constraint(equalToConstant: 70).isActive = true
        ref.heightAnchor.constraint(equalToConstant: 50).isActive = true
        let l1 = NSTextField(labelWithString: "Jouw LED-wit"); l1.font = .systemFont(ofSize: 10)
        let l2 = NSTextField(labelWithString: "Echt wit"); l2.font = .systemFont(ofSize: 10)
        let a = NSStackView(views: [wbSwatch, l1]); a.orientation = .vertical; a.spacing = 2
        let b = NSStackView(views: [ref, l2]); b.orientation = .vertical; b.spacing = 2
        wbInfo = NSTextField(labelWithString: "")
        wbInfo.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let sliders = NSStackView(views: [
            wbRow("Rood", \.wbR, .systemRed),
            wbRow("Groen", \.wbG, .systemGreen),
            wbRow("Blauw", \.wbB, .systemBlue),
        ])
        sliders.orientation = .vertical
        sliders.alignment = .leading
        sliders.spacing = 6
        let preview = NSStackView(views: [a, b])
        preview.spacing = 12
        let top = NSStackView(views: [sliders, preview])
        top.spacing = 24
        top.alignment = .top
        box.addArrangedSubview(top)
        box.addArrangedSubview(wbInfo)

        func preset(_ r: Double, _ g: Double, _ bl: Double) {
            update { $0.wbR = r; $0.wbG = g; $0.wbB = bl }
            eng.setMode(.white)
            refreshWB()
            // sliders volgen de nieuwe waarden
            wbSliders.forEach { $0.0.doubleValue = $0.1() }
        }
        box.addArrangedSubview(NSStackView(views: [
            button("Wit scherm testen…") { [unowned self] in self.showWhiteScreen() },
            button("Wit tonen") { [unowned self] in self.eng.setMode(.white) },
            button("Neutraal") { preset(1, 1, 1) },
            button("Warmer") { preset(1, 0.85, 0.6) },
            button("Koeler") { preset(0.8, 0.95, 1) },
            button("Stop test") { [unowned self] in self.eng.restoreMode() },
        ]))
        refreshWB()
        return box
    }

    var wbSliders: [(NSSlider, () -> Double)] = []

    func wbRow(_ title: String, _ kp: WritableKeyPath<Config, Double>, _ color: NSColor) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.widthAnchor.constraint(equalToConstant: 50).isActive = true
        let val = NSTextField(labelWithString: "")
        val.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        val.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let sl = NSSlider(value: eng.cfg[keyPath: kp], minValue: 0.2, maxValue: 1, target: nil, action: nil)
        sl.trackFillColor = color
        sl.widthAnchor.constraint(equalToConstant: 200).isActive = true
        val.stringValue = "\(Int(eng.cfg[keyPath: kp] * 100))%"
        _ = bind(sl) { [unowned self] s in
            self.update { $0[keyPath: kp] = s.doubleValue }
            val.stringValue = "\(Int(s.doubleValue * 100))%"
            self.eng.setMode(.white)
            self.refreshWB()
        }
        wbSliders.append((sl, { [unowned self] in self.eng.cfg[keyPath: kp] }))
        return NSStackView(views: [lbl, sl, val])
    }

    func refreshWB() {
        let c = eng.cfg
        wbSwatch?.layer?.backgroundColor = NSColor(red: c.wbR, green: c.wbG, blue: c.wbB, alpha: 1).cgColor
        wbInfo?.stringValue = String(format: "Verzonden wit: R %d  G %d  B %d  (van 255)", Int(c.wbR * 255), Int(c.wbG * 255), Int(c.wbB * 255))
    }

    // MARK: Schermvlakken-overlay

    var zoneWindow: NSWindow?
    var zoneView: ZoneOverlayView?
    let zoneInfo = NSTextField(labelWithString: "")

    func showZones() {
        if let w = zoneWindow { w.makeKeyAndOrderFront(nil); return }
        guard let screen = NSScreen.screens.first else { return }
        let w = KeyWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = ZoneOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        w.contentView = v

        // bedieningspaneel in het midden
        let panel = NSVisualEffectView()
        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Schermvlakken controleren")
        title.font = .boldSystemFont(ofSize: 16)
        let help = NSTextField(wrappingLabelWithString: "Elk vak is het stuk scherm dat bij één LED hoort; het nummer is de LED. Klik op een vak: die LED gaat geel/wit branden. Brandt er een LED op een andere plek achter je tv? Verschuif met ◀ ▶ (of de pijltjestoetsen) tot het licht precies achter dat vak zit. Loopt het de verkeerde kant op: Richting omdraaien (R). Esc = sluiten.")
        help.widthAnchor.constraint(equalToConstant: 440).isActive = true
        zoneInfo.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let rev = bind(NSButton(checkboxWithTitle: "Richting omdraaien (R)", target: nil, action: nil)) { [unowned self] b in
            self.update { $0.reversed = (b.state == .on) }
            self.zoneChanged()
        }
        rev.state = eng.cfg.reversed ? .on : .off
        let row = NSStackView(views: [
            button("◀ 10") { [unowned self] in self.shiftZones(-10) },
            button("◀ 1") { [unowned self] in self.shiftZones(-1) },
            button("1 ▶") { [unowned self] in self.shiftZones(1) },
            button("10 ▶") { [unowned self] in self.shiftZones(10) },
            rev,
        ])
        let row2 = NSStackView(views: [
            button("Zijden-test") { [unowned self] in v.selectedP = -1; self.eng.setMode(.sides); v.needsDisplay = true },
            button("Alles wit") { [unowned self] in v.selectedP = -1; self.eng.setMode(.white); v.needsDisplay = true },
            button("Sluiten (Esc)") { [unowned self] in self.closeZones() },
        ])
        let st = NSStackView(views: [title, help, zoneInfo, row, row2])
        st.orientation = .vertical
        st.alignment = .leading
        st.spacing = 10
        st.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        st.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(st)
        v.addSubview(panel)
        NSLayoutConstraint.activate([
            st.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            st.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            st.topAnchor.constraint(equalTo: panel.topAnchor),
            st.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            panel.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])

        v.onPick = { [unowned self] p in
            v.selectedP = p
            self.zoneChanged()
        }
        v.onKey = { [unowned self] e in
            switch e.keyCode {
            case 53: self.closeZones()
            case 123: self.shiftZones(e.modifierFlags.contains(.shift) ? -10 : -1)
            case 124: self.shiftZones(e.modifierFlags.contains(.shift) ? 10 : 1)
            case 15:
                self.update { $0.reversed.toggle() }
                rev.state = self.eng.cfg.reversed ? .on : .off
                self.zoneChanged()
            default: break
            }
        }
        zoneWindow = w
        zoneView = v
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
        eng.setMode(.sides)
        zoneChanged()
    }

    func shiftZones(_ d: Int) {
        update { c in
            let n = max(1, c.total)
            c.offset = ((c.offset + d) % n + n) % n
        }
        offsetLabel.stringValue = "Startpositie: \(eng.cfg.offset)"
        zoneChanged()
    }

    func zoneChanged() {
        guard let v = zoneView else { return }
        let c = eng.cfg
        let n = c.total
        if v.selectedP >= 0 && n > 0 {
            let i = dataIndex(forPerimeter: v.selectedP, n, c)
            eng.setMode(.single(i))
            zoneInfo.stringValue = "Geselecteerd vak → LED \(i + 1)   ·   startpositie \(c.offset)"
        } else {
            zoneInfo.stringValue = "Klik op een vak   ·   startpositie \(c.offset)"
        }
        v.needsDisplay = true
    }

    func closeZones() {
        zoneWindow?.orderOut(nil)
        zoneWindow = nil
        zoneView = nil
        eng.restoreMode()
    }

    // MARK: Wit testscherm

    var whiteWindow: NSWindow?

    func showWhiteScreen() {
        if let w = whiteWindow { w.makeKeyAndOrderFront(nil); return }
        guard let screen = NSScreen.screens.first else { return }
        let w = KeyWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.backgroundColor = .white
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = ZoneOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size)) // alleen voor Esc
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.cgColor
        w.contentView = NSView(frame: v.frame)
        w.contentView?.wantsLayer = true
        w.contentView?.layer?.backgroundColor = NSColor.white.cgColor

        let panel = NSVisualEffectView()
        panel.material = .popover
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.appearance = NSAppearance(named: .aqua)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Witbalans")
        title.font = .boldSystemFont(ofSize: 15)
        let help = NSTextField(wrappingLabelWithString: "Het scherm is nu helemaal wit en alle LEDs branden wit. Verschuif de kanalen tot het licht achter je tv dezelfde kleur wit heeft als je scherm. Te blauw → blauw omlaag, te groen → groen omlaag.")
        help.widthAnchor.constraint(equalToConstant: 360).isActive = true
        func preset(_ r: Double, _ g: Double, _ b: Double) {
            update { $0.wbR = r; $0.wbG = g; $0.wbB = b }
            refreshWB()
            wbSliders.forEach { $0.0.doubleValue = $0.1() }
            eng.setMode(.white)
        }
        let st = NSStackView(views: [
            title, help,
            wbRow("Rood", \.wbR, .systemRed),
            wbRow("Groen", \.wbG, .systemGreen),
            wbRow("Blauw", \.wbB, .systemBlue),
            NSStackView(views: [
                button("Neutraal") { preset(1, 1, 1) },
                button("Warmer") { preset(1, 0.85, 0.6) },
                button("Koeler") { preset(0.8, 0.95, 1) },
                button("Klaar") { [unowned self] in self.closeWhiteScreen() },
            ]),
        ])
        st.orientation = .vertical
        st.alignment = .leading
        st.spacing = 10
        st.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        st.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(st)
        w.contentView?.addSubview(panel)
        NSLayoutConstraint.activate([
            st.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            st.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            st.topAnchor.constraint(equalTo: panel.topAnchor),
            st.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            panel.centerXAnchor.constraint(equalTo: w.contentView!.centerXAnchor),
            panel.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor, constant: -60),
        ])
        whiteWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        eng.setMode(.white)
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53, self?.whiteWindow != nil { self?.closeWhiteScreen(); return nil }
            return e
        }
    }

    var escMonitor: Any?

    func closeWhiteScreen() {
        whiteWindow?.orderOut(nil)
        whiteWindow = nil
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        eng.restoreMode()
    }

    // MARK: LED-indicatievenster

    func showMap() {
        if let w = mapWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let c = eng.cfg
        let view = LEDMapView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.widthAnchor.constraint(equalToConstant: 640).isActive = true
        view.heightAnchor.constraint(equalToConstant: 400).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        stack.addArrangedSubview(view)
        stack.addArrangedSubview(mapStatus)

        offsetLabel.stringValue = "Startpositie: \(c.offset)"
        offsetLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        func shift(_ d: Int) {
            update { $0.offset = (($0.offset + d) % max(1, $0.total) + max(1, $0.total)) % max(1, $0.total) }
            offsetLabel.stringValue = "Startpositie: \(eng.cfg.offset)"
        }
        let rev = bind(NSButton(checkboxWithTitle: "Richting omdraaien", target: nil, action: nil)) { [unowned self] b in
            self.update { $0.reversed = (b.state == .on) }
        }
        rev.state = c.reversed ? .on : .off
        let pos = NSStackView(views: [
            offsetLabel,
            button("−10") { shift(-10) }, button("−1") { shift(-1) },
            button("+1") { shift(1) }, button("+10") { shift(10) },
            rev,
        ])
        pos.spacing = 8
        stack.addArrangedSubview(pos)

        let tests = NSStackView(views: [
            button("Zijden-test") { [unowned self] in self.eng.setMode(.sides) },
            button("Looplicht") { [unowned self] in self.eng.setMode(.chase) },
            button("Alles wit") { [unowned self] in self.eng.setMode(.white) },
            button("Live Ambilight") { [unowned self] in self.eng.restoreMode() },
            button("Schermvlakken…") { [unowned self] in self.showZones() },
        ])
        tests.spacing = 8
        stack.addArrangedSubview(tests)

        let sLbl = NSTextField(labelWithString: "Eén LED aan:")
        let sl = NSSlider(value: 0, minValue: 0, maxValue: Double(max(1, c.total - 1)), target: nil, action: nil)
        sl.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let sv = NSTextField(labelWithString: "LED 1")
        sv.widthAnchor.constraint(equalToConstant: 70).isActive = true
        _ = bind(sl) { [unowned self] s in
            let k = Int(s.doubleValue.rounded())
            sv.stringValue = "LED \(k + 1)"
            self.eng.setMode(.single(k))
        }
        stack.addArrangedSubview(NSStackView(views: [sLbl, sl, sv]))
        view.onPick = { [unowned self] i in
            self.eng.setMode(.single(i))
            sl.doubleValue = Double(i)
            sv.stringValue = "LED \(i + 1)"
        }

        let hint = NSTextField(wrappingLabelWithString: "Wit omcirkeld = LED 1 (eerste LED aan de Arduino-kant), laatste LED heeft het hoogste nummer. De bolletjes tonen live wat er naar de LEDs gaat. Klopt de plek van LED 1 niet met je tv: verschuif de startpositie. Loopt de richting verkeerd om: draai om.")
        hint.widthAnchor.constraint(equalToConstant: 600).isActive = true
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

        stack.layoutSubtreeIfNeeded()
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: stack.fittingSize),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "LED-indicatie"
        w.contentView = stack
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mapWindow = w
        eng.setMode(.sides)
        mapTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in view.needsDisplay = true; self?.refreshStatus() }
    }

    func windowWillClose(_ notification: Notification) {
        eng.restoreMode()
        if (notification.object as? NSWindow) === mapWindow {
            mapTimer?.invalidate(); mapTimer = nil; mapWindow = nil
        } else {
            setupTimer?.invalidate(); setupTimer = nil
            window = nil
        }
    }
}

// MARK: - Schermvlakken-overlay (zoals Prismatik)

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// data-index van de LED die bij schermpositie p hoort
func dataIndex(forPerimeter p: Int, _ n: Int, _ c: Config) -> Int {
    let d = c.reversed ? (c.offset - p) : (p - c.offset)
    return ((d % n) + n) % n
}

final class ZoneOverlayView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var selectedP = -1
    var onPick: ((Int) -> Void)?
    var onKey: ((NSEvent) -> Void)?

    override func keyDown(with e: NSEvent) { onKey?(e) }

    func zoneRect(_ p: Int, _ c: Config) -> CGRect {
        let (s, k, cnt) = locate(p, c)
        let w = bounds.width, h = bounds.height
        let d = max(4, CGFloat(c.depth) * h)
        let K = CGFloat(k), C = CGFloat(max(1, cnt))
        switch s {
        case 0: return CGRect(x: K * w / C, y: 0, width: w / C, height: d)
        case 1: return CGRect(x: w - d, y: K * h / C, width: d, height: h / C)
        case 2: return CGRect(x: w - (K + 1) * w / C, y: h - d, width: w / C, height: d)
        default: return CGRect(x: 0, y: h - (K + 1) * h / C, width: d, height: h / C)
        }
    }

    override func draw(_ dirty: NSRect) {
        NSColor(white: 0, alpha: 0.55).setFill()
        bounds.fill()
        let c = Engine.shared.cfg
        let n = c.total
        guard n > 0 else { return }
        for p in 0..<n {
            let r = zoneRect(p, c).insetBy(dx: 0.5, dy: 0.5)
            let i = dataIndex(forPerimeter: p, n, c)
            let fill: NSColor = p == selectedP
                ? NSColor.systemYellow.withAlphaComponent(0.95)
                : NSColor(calibratedHue: CGFloat(p) / CGFloat(n), saturation: 0.7, brightness: 0.9, alpha: 0.55)
            fill.setFill()
            r.fill()
            NSColor(white: 1, alpha: 0.7).setStroke()
            let b = NSBezierPath(rect: r); b.lineWidth = 1; b.stroke()
            let fs = max(7, min(15, min(r.width, r.height) * 0.42))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fs, weight: .semibold),
                .foregroundColor: p == selectedP ? NSColor.black : NSColor.white,
            ]
            let str = "\(i + 1)" as NSString
            let sz = str.size(withAttributes: attrs)
            if sz.width < r.width + 2 || r.width > r.height {
                str.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2), withAttributes: attrs)
            }
        }
    }

    override func mouseDown(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        let c = Engine.shared.cfg
        for p in 0..<c.total where zoneRect(p, c).contains(pt) { onPick?(p); return }
    }
}

// MARK: - LED-kaart

final class LEDMapView: NSView {
    override var isFlipped: Bool { true }
    var positions: [CGPoint] = []
    var onPick: ((Int) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        var best = -1
        var bd: CGFloat = 20 * 20
        for (i, q) in positions.enumerated() {
            let d = (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)
            if d < bd { bd = d; best = i }
        }
        if best >= 0 { onPick?(best) }
    }

    func text(_ s: String, at p: CGPoint, size: CGFloat = 10, color: NSColor = .secondaryLabelColor, center: Bool = true) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color]
        let sz = (s as NSString).size(withAttributes: attrs)
        let o = center ? CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2) : p
        (s as NSString).draw(at: o, withAttributes: attrs)
    }

    override func draw(_ dirty: NSRect) {
        let eng = Engine.shared
        let c = eng.cfg
        let n = c.total
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let tv = bounds.insetBy(dx: 60, dy: 50)
        let body = NSBezierPath(roundedRect: tv, xRadius: 8, yRadius: 8)
        NSColor(white: 0.1, alpha: 1).setFill()
        body.fill()
        NSColor.gray.setStroke()
        body.lineWidth = 2
        body.stroke()
        text("Voorkant van de tv", at: CGPoint(x: tv.midX, y: tv.midY), size: 13, color: NSColor(white: 0.5, alpha: 1))
        guard n > 0 else {
            text("Vul eerst het aantal LEDs in bij Instellingen", at: CGPoint(x: tv.midX, y: tv.midY + 24), size: 11)
            return
        }
        text("Boven (\(c.top))", at: CGPoint(x: tv.midX, y: tv.minY + 16), color: NSColor(white: 0.55, alpha: 1))
        text("Onder (\(c.bottom))", at: CGPoint(x: tv.midX, y: tv.maxY - 16), color: NSColor(white: 0.55, alpha: 1))
        text("Rechts (\(c.right))", at: CGPoint(x: tv.maxX - 40, y: tv.midY + 40), color: NSColor(white: 0.55, alpha: 1))
        text("Links (\(c.left))", at: CGPoint(x: tv.minX + 36, y: tv.midY + 40), color: NSColor(white: 0.55, alpha: 1))

        let disp = eng.displayColors()
        var selected = -1
        if case .single(let k) = eng.mode { selected = k }
        var pts = [CGPoint](repeating: .zero, count: n)
        for i in 0..<n {
            let p = perimeterIndex(i, n, c)
            let (s, k, cnt) = locate(p, c)
            let f = (CGFloat(k) + 0.5) / CGFloat(cnt)
            var pt = CGPoint.zero
            var len: CGFloat = 0
            switch s {
            case 0: pt = CGPoint(x: tv.minX + f * tv.width, y: tv.minY - 16); len = tv.width
            case 1: pt = CGPoint(x: tv.maxX + 16, y: tv.minY + f * tv.height); len = tv.height
            case 2: pt = CGPoint(x: tv.maxX - f * tv.width, y: tv.maxY + 16); len = tv.width
            default: pt = CGPoint(x: tv.minX - 16, y: tv.maxY - f * tv.height); len = tv.height
            }
            let r = min(7, max(2.5, len / CGFloat(cnt) * 0.42))
            var col = NSColor(white: 0.3, alpha: 1)
            if disp.count == 3 * n {
                let rr = CGFloat(disp[3 * i]) / 255, gg = CGFloat(disp[3 * i + 1]) / 255, bb = CGFloat(disp[3 * i + 2]) / 255
                col = NSColor(red: 0.2 * 0.3 + 0.8 * rr, green: 0.2 * 0.3 + 0.8 * gg, blue: 0.2 * 0.3 + 0.8 * bb, alpha: 1)
            }
            pts[i] = pt
            let dot = NSBezierPath(ovalIn: NSRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r))
            col.setFill(); dot.fill()
            NSColor(white: 0.55, alpha: 1).setStroke(); dot.lineWidth = 0.5; dot.stroke()

            // labels buiten de bolletjes
            let out: CGPoint = {
                switch s {
                case 0: return CGPoint(x: pt.x, y: pt.y - 16)
                case 1: return CGPoint(x: pt.x + 18, y: pt.y)
                case 2: return CGPoint(x: pt.x, y: pt.y + 16)
                default: return CGPoint(x: pt.x - 18, y: pt.y)
                }
            }()
            if i == selected {
                let ring2 = NSBezierPath(ovalIn: NSRect(x: pt.x - r - 3, y: pt.y - r - 3, width: 2 * r + 6, height: 2 * r + 6))
                NSColor.systemYellow.setStroke(); ring2.lineWidth = 2; ring2.stroke()
                text("LED \(i + 1)", at: out, size: 11, color: .systemYellow)
            }
            if i == 0 {
                let ring = NSBezierPath(ovalIn: NSRect(x: pt.x - r - 4, y: pt.y - r - 4, width: 2 * r + 8, height: 2 * r + 8))
                NSColor.white.setStroke(); ring.lineWidth = 2; ring.stroke()
                text("LED 1", at: out, size: 11, color: .labelColor)
            } else if i == n - 1 {
                text("LED \(n)", at: out, size: 11, color: .labelColor)
            } else if (i + 1) % 10 == 0 && cnt >= 6 {
                text("\(i + 1)", at: out, size: 9)
            }
        }
        positions = pts
        text("Klik op een LED om hem aan te zetten · wit omcirkeld = LED 1 · LED \(n) is de laatste", at: CGPoint(x: bounds.midX, y: bounds.maxY - 8), size: 10)
    }
}

// MARK: - Automatisch starten/stoppen

let watcherPlist = "nl.local.ambilight.watcher.plist"
var lockFD: Int32 = -1

func lockFilePath() -> String {
    let dir = NSHomeDirectory() + "/Library/Application Support/Ambilight"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir + "/running.lock"
}

// true = gelukt (wij zijn de enige draaiende app); het slot blijft vast zolang de app leeft
func acquireRunLock() -> Bool {
    lockFD = open(lockFilePath(), O_CREAT | O_RDWR, 0o644)
    guard lockFD >= 0 else { return true }
    return flock(lockFD, LOCK_EX | LOCK_NB) == 0
}

func isMainRunning() -> Bool {
    let fd = open(lockFilePath(), O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    if flock(fd, LOCK_EX | LOCK_NB) == 0 { flock(fd, LOCK_UN); return false }
    return true
}

func arduinoPresent() -> Bool {
    let p = Config.load().port
    return p.isEmpty ? !availablePorts().isEmpty : FileManager.default.fileExists(atPath: p)
}

// Gewone LaunchAgent (~/Library/LaunchAgents). Anders dan SMAppService is die niet aan de
// handtekening van een specifieke build vastgepind, dus hij blijft werken na elke nieuwe build.
enum Agent {
    static let label = "nl.local.ambilight.autostart"
    static var plistPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist" }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    @discardableResult
    static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func install() {
        let exe = Bundle.main.executablePath ?? ""
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, "--watch"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
        ]
        try? FileManager.default.createDirectory(atPath: (plistPath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        (dict as NSDictionary).write(toFile: plistPath, atomically: true)
        let dom = "gui/\(getuid())"
        launchctl(["bootout", "\(dom)/\(label)"])
        launchctl(["bootstrap", dom, plistPath])
    }

    static func uninstall() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    // Oude SMAppService-registratie opruimen en de keuze van de gebruiker meenemen.
    static func migrateFromServiceManagement() {
        let s = SMAppService.agent(plistName: watcherPlist)
        if s.status == .enabled || s.status == .requiresApproval {
            try? s.unregister()
            install()
        }
    }
}

// Onzichtbare hulp-agent: start de app zodra de Arduino wordt aangesloten.
func runWatcher() -> Never {
    var lastLaunch = Date.distantPast
    while true {
        if arduinoPresent() && Date().timeIntervalSince(lastLaunch) > 20 && !isMainRunning() {
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            t.arguments = ["-n", Bundle.main.bundlePath, "--args", "--auto"]
            try? t.run()
            lastLaunch = Date()
        }
        Thread.sleep(forTimeInterval: 2)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var modeItems: [NSMenuItem] = []
    let arduinoLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let login = NSMenuItem(title: "Start bij inloggen", action: #selector(toggleLogin), keyEquivalent: "")
    var slider: NSSlider!
    let setup = SetupController()

    func applicationDidFinishLaunching(_ n: Notification) {
        // Draait er al een Ambilight? Dan die gebruiken en deze kopie meteen sluiten.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty || !acquireRunLock() {
            others.first?.activate()
            NSApp.terminate(nil)
            return
        }
        startAutoQuitWatch()
        if !CommandLine.arguments.contains("--auto") {
            DispatchQueue.global().async { refreshAgentRegistration() }
        }
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "lightbulb.led.fill", accessibilityDescription: "Ambilight")
            ?? NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "Ambilight")

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        arduinoLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(arduinoLine)
        menu.addItem(.separator())
        for (i, name) in ["Uit", "Ambilight (scherm volgen)", "Statische kleur", "Animatie"].enumerated() {
            let mi = NSMenuItem(title: name, action: #selector(setKind(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            menu.addItem(mi)
            modeItems.append(mi)
        }

        let bri = NSMenuItem()
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        let lbl = NSTextField(labelWithString: "Helderheid")
        lbl.frame = NSRect(x: 14, y: 6, width: 70, height: 17)
        slider = NSSlider(value: Engine.shared.cfg.brightness, minValue: 0, maxValue: 1, target: self, action: #selector(brightnessChanged(_:)))
        slider.frame = NSRect(x: 88, y: 5, width: 120, height: 20)
        slider.isContinuous = true
        v.addSubview(lbl); v.addSubview(slider)
        bri.view = v
        menu.addItem(bri)

        menu.addItem(.separator())
        let s = NSMenuItem(title: "Instellingen…", action: #selector(openSetup), keyEquivalent: ",")
        s.target = self
        menu.addItem(s)
        let m = NSMenuItem(title: "LED-indicatie…", action: #selector(openMap), keyEquivalent: "")
        m.target = self
        menu.addItem(m)
        let z = NSMenuItem(title: "Schermvlakken tonen…", action: #selector(openZones), keyEquivalent: "")
        z.target = self
        menu.addItem(z)
        let wsi = NSMenuItem(title: "Wit testscherm…", action: #selector(openWhite), keyEquivalent: "")
        wsi.target = self
        menu.addItem(wsi)
        let ex = NSMenuItem(title: "Instellingen exporteren…", action: #selector(exportSettings), keyEquivalent: "")
        ex.target = self
        menu.addItem(ex)
        let im = NSMenuItem(title: "Instellingen importeren…", action: #selector(importSettings), keyEquivalent: "")
        im.target = self
        menu.addItem(im)
        autoItem = NSMenuItem(title: "Automatisch starten bij aansluiten", action: #selector(toggleAuto), keyEquivalent: "")
        autoItem.target = self
        menu.addItem(autoItem)
        login.target = self
        menu.addItem(login)
        let perm = NSMenuItem(title: "Schermopname-toestemming…", action: #selector(openPrivacy), keyEquivalent: "")
        perm.target = self
        menu.addItem(perm)
        menu.addItem(.separator())
        let q = NSMenuItem(title: "Afsluiten", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
        item.menu = menu

        let eng = Engine.shared
        eng.mode = eng.modeFromConfig()
        eng.start()
        if !CommandLine.arguments.contains("--auto") { setup.show() }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Engine.shared.setMode(.off)
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Engine.shared.restoreMode()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setup.show()
        return true
    }

    var missingSecs = 0
    var seenArduino = false
    let launchedAt = Date()
    var autoItem: NSMenuItem!

    func startAutoQuitWatch() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if arduinoPresent() { self.missingSecs = 0; self.seenArduino = true; return }
            self.missingSecs += 2
            let grace = self.seenArduino ? 6 : 20     // net gestart zonder Arduino: iets meer tijd
            if Agent.isInstalled && self.missingSecs >= grace {
                NSApp.terminate(nil)
            }
        }
    }

    @objc func toggleAuto() {
        if Agent.isInstalled { Agent.uninstall() } else { Agent.install() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        autoItem.state = Agent.isInstalled ? .on : .off
        autoItem.title = "Automatisch starten bij aansluiten"
        let c = Engine.shared.cfg
        let (t, _) = Engine.shared.captureStatus()
        statusLine.title = "Schermopname: " + t
        arduinoLine.title = "Arduino: " + Engine.shared.arduinoStatus
        for mi in modeItems { mi.state = kindNames[mi.tag] == c.kind ? .on : .off }
        slider.doubleValue = c.brightness
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func setKind(_ mi: NSMenuItem) {
        var c = Engine.shared.cfg
        c.kind = kindNames[mi.tag]
        Engine.shared.cfg = c
        Engine.shared.restoreMode()
    }

    @objc func brightnessChanged(_ s: NSSlider) {
        var c = Engine.shared.cfg
        c.brightness = s.doubleValue
        Engine.shared.cfg = c
    }

    @objc func exportSettings() { SettingsIO.export() }
    @objc func importSettings() {
        SettingsIO.importFile { [unowned self] in
            if self.setup.window != nil {
                self.setup.window.close()
                DispatchQueue.main.async { self.setup.show() }
            }
        }
    }
    @objc func openSetup() { setup.show() }
    @objc func openMap() { setup.showMap() }
    @objc func openZones() { setup.showZones() }
    @objc func openWhite() { setup.showWhiteScreen() }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }

    @objc func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc func quit() {
        Engine.shared.shutdown()
        NSApp.terminate(nil)
    }
}

// Na een nieuwe build: oude registratie opruimen en de agent opnieuw starten met de nieuwe app.
func refreshAgentRegistration() {
    Agent.migrateFromServiceManagement()
    if Agent.isInstalled { Agent.install() }
}

if CommandLine.arguments.contains("--watch") { runWatcher() }
if CommandLine.arguments.contains("--refresh-agent") { refreshAgentRegistration(); exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
