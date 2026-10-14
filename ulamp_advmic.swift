// ulamp_advmic — beacon uac* da fita vs estado do modo música + ruído ambiente.
// Fases: conecta → aplica modo música (on/off) → desconecta → escuta advertisements.
// Uso: ./ulamp_advmic <on|off|none> <duracao_seg>
import Foundation
import CoreBluetooth

let SVC = CBUUID(string: "FFB0"), W = CBUUID(string: "FFB1"), N = CBUUID(string: "FFB2")
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "none"                  // on | off | none
let dur = args.count > 2 ? (Double(args[2]) ?? 15.0) : 15.0

var tid: UInt8 = UInt8.random(in: 0...255)
func pk(_ cmd: UInt8, _ a: [UInt8] = []) -> [UInt8] { [0x0A, 0xA5, tid, cmd] + a }
// música: <open> <musicMode> <dir> <sens> <count> <rgb...>
let pkt: [UInt8]? = mode == "on"  ? pk(0x06, [0x01, 0x01, 0x00, 0x50, 0x01, 0xFF, 0x00, 0x00])
             : mode == "off" ? pk(0x06, [0x00, 0x00, 0x00, 0x50, 0x01, 0xFF, 0x00, 0x00])
             : nil

let t0 = Date()
setbuf(stdout, nil)
print("=== modo=\(mode) dur=\(dur)s — coopere conforme instruído ===")

class S: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var cm: CBCentralManager!
    var p: CBPeripheral?
    var wc: CBCharacteristic?
    var sent = false, scanning = false
    var n = 0
    var lastMfr = ""

    override init() { super.init(); cm = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { print("bt off"); exit(1) }
        if let pkt {                       // fase 1: conectar e aplicar comando
            c.scanForPeripherals(withServices: [SVC], options: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if self?.p == nil, self?.scanning == false { print("fita não achada"); exit(2) }
            }
        } else { startScan(c) }            // pula direto para a escuta
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !scanning {                     // fase conexão
            guard self.p == nil else { return }
            self.p = p; p.delegate = self; c.stopScan(); c.connect(p, options: nil)
            print("[\(t())] conectando \(p.name ?? "?")…")
        } else if p.name?.lowercased().hasPrefix("uac") == true {
            let mfr = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?
                .map { String(format: "%02x", $0) }.joined() ?? "-"
            let svcData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])?
                .map { "\($0.key.uuidString.suffix(4))=\($0.value.map { String(format: "%02x", $0) }.joined())" }
                .joined(separator: " ") ?? ""
            n += 1
            let tag = mfr == lastMfr ? "" : "  << MUDOU"
            print("[\(t())] #\(n) \(p.name ?? "?") rssi=\(RSSI.intValue) mfr=\(mfr) svc=\(svcData)\(tag)")
            lastMfr = mfr
        }
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([SVC]) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics([W, N], for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] { if ch.uuid == W { wc = ch } }
        guard let wc, !sent else { return }
        sent = true
        p.writeValue(Data(pkt!), for: wc, type: .withoutResponse)
        print("[\(t())] comando música \(mode) enviado")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.cm.cancelPeripheralConnection(p)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.startScan(self!.cm)
            }
        }
    }

    func startScan(_ c: CBCentralManager) {
        scanning = true; p = nil
        print("[\(t())] escutando advertisements por \(dur)s…")
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
            print("=== fim: \(self.n) frames ==="); exit(0)
        }
    }
    func t() -> String { String(format: "%6.2f", Date().timeIntervalSince(t0)) }
}

var s: S? = S()
dispatchMain()
