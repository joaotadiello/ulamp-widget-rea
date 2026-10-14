// uLamp Widget — widget flutuante + barra de menus para a fita uLamp (88006190)
// Protocolo validado: 0A A5 <TID> <CMD> <ARGS> em FFB1, notificações em FFB2.
// Build: swiftc -O uLampWidget.swift -o uLampWidget -framework AppKit -framework CoreBluetooth -framework ScreenCaptureKit

import AppKit
import CoreBluetooth
import ScreenCaptureKit

// MARK: - Motor BLE

final class Lamp: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = Lamp()
    var cm: CBCentralManager!
    var peripheral: CBPeripheral?
    var writeChar: CBCharacteristic?
    var tid: UInt8 = UInt8.random(in: 0...255)
    var connected = false
    var powered = false

    var onStatus: ((String) -> Void)?
    var onPowered: ((Bool) -> Void)?
    var onMusic: ((Bool) -> Void)?

    /// Modo música = mic da própria fita (DSP interno). sens 1-100.
    var musicOn = false
    var musicSens: UInt8 = 80
    private var musicColor: (UInt8, UInt8, UInt8) = (0xFF, 0xFF, 0xFF)

    private var desired: [UInt8]?
    private var drainTimer: Timer?

    let SVC = CBUUID(string: "FFB0"), W = CBUUID(string: "FFB1"), N = CBUUID(string: "FFB2")

    override init() {
        super.init()
        cm = CBCentralManager(delegate: self, queue: nil)
        drainTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            self?.drain()
        }
    }

    private func drain() {
        guard connected, let char = writeChar, let data = desired else { return }
        guard peripheral?.canSendWriteWithoutResponse ?? true else { return }
        desired = nil
        peripheral?.writeValue(Data(data), for: char, type: .withoutResponse)
    }

    func packet(_ cmd: UInt8, _ args: [UInt8]) -> [UInt8] { [0x0A, 0xA5, tid &+ 1, cmd] + args }

    func send(_ cmd: UInt8, _ args: [UInt8]) { desired = packet(cmd, args) }
    func power(_ on: Bool) { powered = on; onPowered?(on); send(0x01, [on ? 1 : 0]) }
    func paint(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ bri: Int) {
        send(0x04, [1, 1, 1, UInt8(max(1, min(100, bri))), r, g, b])
    }
    func paintMulti(_ colors: [(UInt8, UInt8, UInt8)], _ bri: Int) {
        var args: [UInt8] = [1, 1, UInt8(colors.count)]
        for c in colors { args += [UInt8(max(1, min(100, bri))), c.0, c.1, c.2] }
        send(0x04, args)
    }
    func query() { send(0xFF, []) }

    /// `06 <open> <musicMode> <dir> <sens> <count> <r g b>` — open=1 liga o mic da fita.
    func music(_ on: Bool, color: (UInt8, UInt8, UInt8)? = nil) {
        if let color { musicColor = color }
        musicOn = on
        send(0x06, [on ? 1 : 0, on ? 1 : 0, 0, musicSens, 1, musicColor.0, musicColor.1, musicColor.2])
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { scan() } else { ui("Bluetooth desligado") }
    }
    private func scan() {
        ui("procurando…")
        cm.scanForPeripherals(withServices: [SVC], options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, !(self.peripheral?.state == .connected) else { return }
            if self.cm.state == .poweredOn, self.peripheral == nil { self.scan() }
        }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard peripheral?.state != .connected else { return }
        peripheral = p; p.delegate = self
        c.stopScan(); ui("conectando…"); c.connect(p, options: nil)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([SVC])
    }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        connected = false; writeChar = nil; ui("reconectando…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.scan() }
    }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        peripheral = nil; scan()
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics([W, N], for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == W { writeChar = ch }
            if ch.uuid == N { p.setNotifyValue(true, for: ch) }
        }
        if writeChar != nil, !connected {
            connected = true; ui("conectado")
            query()
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value, d.count >= 5, d[0] == 0x0A, d[1] == 0xA5 else { return }
        switch d[3] {
        case 0x01:
            powered = d[4] == 1
            DispatchQueue.main.async { self.onPowered?(self.powered) }
        case 0x06 where d.count >= 5:
            musicOn = d[4] == 1
            DispatchQueue.main.async { self.onMusic?(self.musicOn) }
        default: break
        }
    }
    private func ui(_ s: String) { DispatchQueue.main.async { self.onStatus?(s) } }
}

// MARK: - Modo Ambiente (captura de tela → 5 segmentos)

final class Ambient {
    static let shared = Ambient()
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private(set) var on = false
    var brightness = 100
    var onState: ((Bool) -> Void)?
    var onNotice: ((String) -> Void)?
    var onRestart: (() -> Void)?
    private var fails = 0, restartedOnce = false

    // Zonas (bordas da tela): 0=Esquerda 1=Topo-E 2=Topo-D 3=Direita 4=Base
    // Preset da fita Uascent TV (enrolamento anti-horário, início no topo-esquerdo):
    // seções físicas: 1=Topo-E 2=Esquerda 3=Base 4=Direita 5=Topo-D
    // assign[zone] = seção física (0-4). Inversão esq↔dir disponível no menu da barra.
    private let assign: [Int] = [1, 0, 4, 3, 2]
    var mirrorLR: Bool {
        didSet { dflt.set(mirrorLR, forKey: "mapMirrorLR") }
    }
    private let dflt = UserDefaults.standard

    init() { mirrorLR = dflt.bool(forKey: "mapMirrorLR") }

    /// Retoma o modo Ambiente após reinício (só se a permissão já está ativa — nunca pede prompt sozinho)
    func resumeIfActive() {
        if dflt.bool(forKey: "ambientAuto"), CGPreflightScreenCaptureAccess() { begin() }
    }    /// cores por zona → cores por seção física
    private func mapped(_ zoneColors: [(UInt8, UInt8, UInt8)]) -> [(UInt8, UInt8, UInt8)] {
        var zc = zoneColors
        if mirrorLR { zc.swapAt(0, 3); zc.swapAt(1, 2) }
        var out = zc
        for z in 0..<zc.count { out[assign[z]] = zc[z] }
        return out
    }

    private let W = 100, H = 28, SEGS = 5

    func toggle() { on ? stop() : begin() }

    // Permissão de tela: um pedido por clique. Aprovada → reinicia p/ ativar (TCC só
    // aplica gravação de tela após relançamento). Nunca fica em loop de pedidos.
    private func begin() {
        guard !CGPreflightScreenCaptureAccess() else { start(); return }
        onNotice?("permissão de tela…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let granted = CGRequestScreenCaptureAccess()
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.onNotice?("negada — Ajustes › Privacidade › Gravação de Tela")
                    return
                }
                if CGPreflightScreenCaptureAccess() {
                    self.onNotice?("permissão ok")
                    self.start()
                } else {
                    self.onNotice?("aprovado! reiniciando p/ ativar…")
                    self.onRestart?() // LaunchAgent relança com a permissão ativa
                }
            }
        }
    }

    private func start() {
        on = true; onState?(true)
        dflt.set(true, forKey: "ambientAuto")
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }
    func stop() {
        on = false; onState?(false)
        dflt.set(false, forKey: "ambientAuto")
        timer?.invalidate(); timer = nil
    }

    private func tick() {
        guard on, task == nil else { return }
        task = Task { [weak self] in
            defer { self?.task = nil }
            guard let colors = await self?.captureColors() else {
                // permissão concedida mas captura falha → TCC exige reinício (1x)
                if CGPreflightScreenCaptureAccess() {
                    await MainActor.run { self?.handleCaptureFail() }
                }
                return
            }
            self?.fails = 0
            let bri = self?.brightness ?? 100
            let mapped = self?.mapped(colors) ?? colors
            await MainActor.run {
                if Lamp.shared.connected, Lamp.shared.powered, self?.on == true {
                    Lamp.shared.paintMulti(mapped, bri)
                }
            }
        }
    }

    private func handleCaptureFail() {
        guard on, !restartedOnce else { return }
        fails += 1
        if fails >= 4 {
            restartedOnce = true
            onNotice?("reiniciando p/ aplicar permissão…")
            onRestart?()
        }
    }

    private func captureColors() async -> [(UInt8, UInt8, UInt8)]? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.width = W; cfg.height = H; cfg.showsCursor = false
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 6)
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            return analyze(img)
        } catch { return nil }
    }

    private func analyze(_ img: CGImage) -> [(UInt8, UInt8, UInt8)]? {
        // downsample para WxH (buffer TLO: y=0 é o TOPO da tela — verificado em teste)
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: W * H * 4)

        func avg(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) -> (UInt8, UInt8, UInt8)? {
            var rs = 0, gs = 0, bs = 0, n = 0
            for y in max(0, y0)..<min(H, y1) {
                for x in max(0, x0)..<min(W, x1) {
                    let i = (y * W + x) * 4
                    rs += Int(px[i]); gs += Int(px[i + 1]); bs += Int(px[i + 2]); n += 1
                }
            }
            guard n > 0 else { return nil }
            return (UInt8(rs / n), UInt8(gs / n), UInt8(bs / n))
        }

        // contorno em ordem das zonas: esquerda, topo-E, topo-D, direita, base
        var regions: [(UInt8, UInt8, UInt8)] = []
        let edge = 8, midL = W / 2, midR = W - 7
        for r in [avg(0, 7, 0, H), avg(7, midL, 0, edge),
                  avg(midL, midR, 0, edge), avg(W - 7, W, 0, H),
                  avg(7, W - 7, H - edge, H)] {
            guard let c = r else { return nil }
            regions.append(c)
        }
        guard regions.count == SEGS else { return nil }
        return regions.map { boost($0.0, $0.1, $0.2) }
    }

    // média → boost de saturação/valor para "acender" o ambiente
    private func boost(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> (UInt8, UInt8, UInt8) {
        let r = Double(r8) / 255, g = Double(g8) / 255, b = Double(b8) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        var h: Double = 0, s: Double = mx == 0 ? 0 : (mx - mn) / mx
        let v = mx
        if mx != mn {
            let d = mx - mn
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60; if h < 0 { h += 360 }
        }
        s = min(1, s * 1.8 + 0.05)
        let v2 = min(1, 0.12 + v * 1.15)
        let c = v2 * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v2 - c
        var (r1, g1, b1) = (c, 0.0, 0.0)
        switch h {
        case ..<60: (r1, g1, b1) = (c, x, 0)
        case ..<120: (r1, g1, b1) = (x, c, 0)
        case ..<180: (r1, g1, b1) = (0, c, x)
        case ..<240: (r1, g1, b1) = (0, x, c)
        case ..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return (UInt8(min(255, (r1 + m) * 255)), UInt8(min(255, (g1 + m) * 255)), UInt8(min(255, (b1 + m) * 255)))
    }
}

// MARK: - Painel arrastável

class WidgetPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { true }
}

// Área de arraste (apenas o cabeçalho — cliques nos controles não movem o painel)
class DragView: NSView {
    private var dragOffset: NSPoint?
    override func mouseDown(with e: NSEvent) {
        dragOffset = NSEvent.mouseLocation
        super.mouseDown(with: e)
    }
    override func mouseDragged(with e: NSEvent) {
        guard let off = dragOffset, let win = window else { return }
        let cur = NSEvent.mouseLocation
        let o = win.frame.origin
        win.setFrameOrigin(NSPoint(x: o.x + (cur.x - off.x), y: o.y + (cur.y - off.y)))
        dragOffset = cur
    }
}

// MARK: - UI

class WidgetController: NSObject, NSApplicationDelegate {
    var panel: WidgetPanel!
    var statusItem: NSStatusItem!
    var statusLabel: NSTextField!
    var dot: NSView!
    var powerButton: NSButton!
    var ambientButton: NSButton!
    var musicButton: NSButton!
    var slider: NSSlider!
    var lastColor: (UInt8, UInt8, UInt8) = (0xFF, 0xFF, 0xFF)
    var lastBri = 100

    let swatches: [(String, UInt8, UInt8, UInt8)] = [
        ("Branco", 0xFF, 0xFF, 0xFF), ("Âmbar", 0xFF, 0xBE, 0x78),
        ("Vermelho", 0xFF, 0x00, 0x00), ("Laranja", 0xFF, 0x78, 0x00),
        ("Amarelo", 0xFF, 0xD4, 0x00), ("Verde", 0x00, 0xE6, 0x4D),
        ("Ciano", 0x00, 0xE5, 0xFF), ("Azul", 0x00, 0x66, 0xFF),
        ("Roxo", 0x8A, 0x2B, 0xE2), ("Rosa", 0xFF, 0x2D, 0x95),
    ]

    func applicationDidFinishLaunching(_ n: Notification) {
        buildPanel()
        buildMenuBar()
        Lamp.shared.onStatus = { [weak self] s in self?.setStatus(s) }
        Lamp.shared.onPowered = { [weak self] on in self?.setPowerUI(on) }
        Ambient.shared.onState = { [weak self] on in self?.setAmbientUI(on) }
        Ambient.shared.onNotice = { [weak self] s in self?.setStatus(s) }
        // TCC exige reinício p/ ativar gravação de tela: sai com código ≠ 0 e o
        // LaunchAgent (KeepAlive SuccessfulExit=false) relança automaticamente.
        Ambient.shared.onRestart = { exit(86) }
        Ambient.shared.resumeIfActive() // retoma se estava ativo antes de reiniciar
        Lamp.shared.onMusic = { [weak self] on in self?.setMusicUI(on) }
    }

    // MARK painel
    private func buildPanel() {
        let w: CGFloat = 236, h: CGFloat = 372
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel = WidgetPanel(contentRect: NSRect(x: screen.maxX - w - 24, y: screen.maxY - h - 24,
                                                width: w, height: h),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 18
        bg.layer?.masksToBounds = true

        let root = NSView(frame: bg.bounds)

        // header (arrastável — só esta área move o painel)
        let header = DragView(frame: NSRect(x: 8, y: h - 48, width: w - 16, height: 40))
        let title = NSTextField(labelWithString: "💡 uLamp")
        title.frame = NSRect(x: 8, y: 12, width: 120, height: 20)
        title.font = .boldSystemFont(ofSize: 14)
        header.addSubview(title)
        let close = NSButton(title: "✕", target: self, action: #selector(hidePanel))
        close.frame = NSRect(x: w - 48, y: 10, width: 26, height: 22)
        close.bezelStyle = .texturedRounded
        close.isBordered = false
        close.font = .systemFont(ofSize: 12)
        header.addSubview(close)
        dot = NSView(frame: NSRect(x: w - 66, y: 16, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dot.layer?.cornerRadius = 5
        header.addSubview(dot)
        root.addSubview(header)
        statusLabel = label("iniciando…", 10, color: .secondaryLabelColor, x: 16, y: h - 64, w: w - 32)
        root.addSubview(statusLabel)

        // power
        powerButton = NSButton(title: "Desligada", target: self, action: #selector(togglePower))
        powerButton.frame = NSRect(x: 16, y: h - 104, width: w - 32, height: 40)
        powerButton.bezelStyle = .regularSquare
        powerButton.font = .boldSystemFont(ofSize: 14)
        powerButton.wantsLayer = true
        powerButton.layer?.cornerRadius = 10
        setPowerUI(false)
        root.addSubview(powerButton)

        // ambiente
        ambientButton = NSButton(title: "🎬 Modo Ambiente", target: self, action: #selector(toggleAmbient))
        ambientButton.frame = NSRect(x: 16, y: h - 140, width: w - 32, height: 28)
        ambientButton.bezelStyle = .regularSquare
        ambientButton.font = .systemFont(ofSize: 12, weight: .semibold)
        ambientButton.wantsLayer = true
        ambientButton.layer?.cornerRadius = 8
        ambientButton.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.25).cgColor
        root.addSubview(ambientButton)

        // música (mic da fita) — botão + sensibilidade
        musicButton = NSButton(title: "🎵 Modo Música", target: self, action: #selector(toggleMusic))
        musicButton.frame = NSRect(x: 16, y: h - 174, width: w - 32, height: 28)
        musicButton.bezelStyle = .regularSquare
        musicButton.font = .systemFont(ofSize: 12, weight: .semibold)
        musicButton.wantsLayer = true
        musicButton.layer?.cornerRadius = 8
        musicButton.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.25).cgColor
        setMusicUI(false)
        root.addSubview(musicButton)

        // brilho
        root.addSubview(label("Brilho", 11, bold: false, x: 16, y: h - 200, w: 60))
        slider = NSSlider(value: 100, minValue: 1, maxValue: 100, target: self,
                          action: #selector(briChanged))
        slider.frame = NSRect(x: 70, y: h - 202, width: w - 86, height: 20)
        slider.isContinuous = true
        root.addSubview(slider)
        root.addSubview(label("Sens", 11, bold: false, x: 16, y: h - 226, w: 60))
        let sens = NSSlider(value: Double(Lamp.shared.musicSens), minValue: 1, maxValue: 100,
                            target: self, action: #selector(sensChanged))
        sens.frame = NSRect(x: 70, y: h - 228, width: w - 86, height: 20)
        sens.isContinuous = false
        root.addSubview(sens)

        // cores
        root.addSubview(label("Cores", 11, bold: false, x: 16, y: h - 252, w: 80))
        let cols = 5, sw: CGFloat = (w - 32 - CGFloat(cols - 1) * 8) / CGFloat(cols), sh: CGFloat = 26
        for (i, (name, r, g, b)) in swatches.enumerated() {
            let row = i / cols, col = i % cols
            let b = SwatchButton(color: NSColor(red: CGFloat(r)/255, green: CGFloat(g)/255,
                                                blue: CGFloat(b)/255, alpha: 1), tip: name,
                                 action: { [weak self] in self?.applyColor(r, g, b) })
            b.frame = NSRect(x: 16 + CGFloat(col) * (sw + 8),
                             y: h - 286 - CGFloat(row) * (sh + 8), width: sw, height: sh)
            root.addSubview(b)
        }

        // seletor custom
        let well = NSColorWell(frame: NSRect(x: 16, y: 16, width: w - 130, height: 30))
        well.color = .white
        well.target = self
        well.action = #selector(customColor(_:))
        root.addSubview(well)
        let rnd = NSButton(title: "Aleatória", target: self, action: #selector(randomColor))
        rnd.frame = NSRect(x: w - 106, y: 16, width: 90, height: 30)
        rnd.bezelStyle = .texturedRounded
        rnd.font = .systemFont(ofSize: 11)
        root.addSubview(rnd)

        bg.addSubview(root)
        panel.contentView = bg
        panel.orderFrontRegardless()
    }

    private func label(_ t: String, _ size: CGFloat, bold: Bool = false,
                       color: NSColor = .labelColor, x: CGFloat, y: CGFloat, w: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.frame = NSRect(x: x, y: y, width: w, height: 16)
        l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        l.textColor = color
        return l
    }

    // MARK barra de menus
    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "💡"
        let m = NSMenu()
        m.addItem(withTitle: "Mostrar/ocultar widget", action: #selector(togglePanel), keyEquivalent: "u")
        m.addItem(.separator())
        m.addItem(withTitle: "Ligar", action: #selector(powerOn), keyEquivalent: "l")
        m.addItem(withTitle: "Desligar", action: #selector(powerOff), keyEquivalent: "d")
        m.addItem(.separator())
        let mir = NSMenuItem(title: "⇄ Inverter esquerda↔direita", action: #selector(toggleMirror), keyEquivalent: "")
        mir.state = Ambient.shared.mirrorLR ? .on : .off
        m.addItem(mir)
        let mic = NSMenuItem(title: "🎵 Modo Música (mic da fita)", action: #selector(toggleMusic), keyEquivalent: "o")
        mic.target = self
        m.addItem(mic)
        m.addItem(.separator())
        m.addItem(withTitle: "Sair", action: #selector(quit), keyEquivalent: "q")
        for it in m.items where it.action == #selector(powerOn) || it.action == #selector(powerOff)
            || it.action == #selector(togglePanel) || it.action == #selector(quit)
            || it.action == #selector(toggleMirror) { it.target = self }
        statusItem.menu = m
    }

    // MARK ações
    @objc func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
    @objc func hidePanel() { panel.orderOut(nil) }
    @objc func powerOn() { Lamp.shared.power(true) }
    @objc func powerOff() { Lamp.shared.power(false) }
    @objc func togglePower() { Lamp.shared.power(!Lamp.shared.powered) }
    @objc func toggleAmbient() { Ambient.shared.toggle() }
    @objc func toggleMusic() {
        Lamp.shared.music(!Lamp.shared.musicOn, color: lastColor)
        setStatus(Lamp.shared.musicOn ? "modo música ativo (mic da fita)" : "modo música off")
    }
    @objc func sensChanged(_ s: NSSlider) {
        Lamp.shared.musicSens = UInt8(max(1, min(100, Int(s.intValue))))
        if Lamp.shared.musicOn { Lamp.shared.music(true) } // reenvia com nova sens.
    }
    @objc func toggleMirror(_ sender: NSMenuItem) {
        Ambient.shared.mirrorLR.toggle()
        sender.state = Ambient.shared.mirrorLR ? .on : .off
    }
    /// Saída limpa (código 0): o LaunchAgent NÃO relança — o app fica fechado
    /// até o próximo login ou até abrir manualmente.
    @objc func quit() { NSApp.terminate(nil) }

    @objc func briChanged() {
        lastBri = Int(slider.intValue)
        Ambient.shared.brightness = lastBri
        if !Ambient.shared.on {
            let c = lastColor
            Lamp.shared.paint(c.0, c.1, c.2, lastBri)
        }
    }
    private func applyColor(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        lastColor = (r, g, b)
        Lamp.shared.paint(r, g, b, lastBri)
    }
    @objc func customColor(_ well: NSColorWell) {
        let c = well.color.usingColorSpace(.deviceRGB) ?? .white
        let r = UInt8(max(0, min(255, Int(round(c.redComponent * 255)))))
        let g = UInt8(max(0, min(255, Int(round(c.greenComponent * 255)))))
        let b = UInt8(max(0, min(255, Int(round(c.blueComponent * 255)))))
        applyColor(r, g, b)
    }
    @objc func randomColor() {
        let r = UInt8.random(in: 0...255), g = UInt8.random(in: 0...255), b = UInt8.random(in: 0...255)
        applyColor(r, g, b)
    }

    // MARK estado
    func setStatus(_ s: String) {
        statusLabel.stringValue = s
        switch s {
        case "conectado", "permissão ok": dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case "Bluetooth desligado": dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        default: dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        }
    }
    func setPowerUI(_ on: Bool) {
        powerButton.title = on ? "Ligada ✅" : "Desligada"
        powerButton.layer?.backgroundColor = (on ? NSColor.systemGreen : NSColor.systemGray)
            .withAlphaComponent(0.35).cgColor
    }
    func setAmbientUI(_ on: Bool) {
        ambientButton.title = on ? "🎬 Ambiente ATIVO" : "🎬 Modo Ambiente"
        ambientButton.layer?.backgroundColor = (on ? NSColor.systemBlue : NSColor.systemGray)
            .withAlphaComponent(0.35).cgColor
    }
    func setMusicUI(_ on: Bool) {
        musicButton.title = on ? "🎵 Música ATIVA (mic da fita)" : "🎵 Modo Música"
        musicButton.layer?.backgroundColor = (on ? NSColor.systemPurple : NSColor.systemGray)
            .withAlphaComponent(0.35).cgColor
    }
}

// MARK: - Botão de cor

class SwatchButton: NSView {
    private var action: () -> Void

    init(color: NSColor, tip: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
        toolTip = tip
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with e: NSEvent) {
        layer?.borderWidth = 3
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.layer?.borderWidth = 1.5
        }
    }
    override func mouseUp(with e: NSEvent) { action() }
}

// MARK: - main

let app = NSApplication.shared
let ctrl = WidgetController()
app.delegate = ctrl
app.setActivationPolicy(.accessory)
app.run()
