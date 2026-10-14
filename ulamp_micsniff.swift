// ulamp_micsniff — testa se a fita transmite dados do microfone dela por BLE.
// Conecta, liga o modo música (opcode 06 = openMusic) e loga TODAS as notificações
// da FFB2 com timestamp. Faça barulho perto da fita durante a captura.
//
// Uso: ./ulamp_micsniff [duracao_seg] [musicMode]
//   musicMode 0 = liga mic (padrão) · passe 1 no fim p/ DESLIGAR o modo música

import Foundation
import CoreBluetooth

let SVC = CBUUID(string: "FFB0"), W = CBUUID(string: "FFB1"), N = CBUUID(string: "FFB2")

let args = CommandLine.arguments
let dur = args.count > 1 ? (Double(args[1]) ?? 20.0) : 20.0
let disable = args.count > 2 && args[2] == "1"

var tid: UInt8 = UInt8.random(in: 0...255)
func pk(_ cmd: UInt8, _ args: [UInt8] = []) -> [UInt8] { [0x0A, 0xA5, tid, cmd] + args }

// comando música do fonte 88006190.lua: <open> <musicMode> <dir> <sens> <count> <r g b>...
let musicOn  = pk(0x06, [0x01, 0x01, 0x00, 0x50, 0x01, 0xFF, 0x00, 0x00])
let musicOff = pk(0x06, [0x00, 0x00, 0x00, 0x50, 0x01, 0xFF, 0x00, 0x00])
let pkt = disable ? musicOff : musicOn

let t0 = Date()
func ts() -> String { String(format: "%7.3f", Date().timeIntervalSince(t0)) }
func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02x", $0) }.joined(separator: " ") }

setbuf(stdout, nil)
print("=== ulamp_micsniff — \(disable ? "DESLIGA" : "LIGA") modo música, escuta \(dur)s — FAÇA BARULHO PERTO DA FITA ===")

class Sniff: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var cm: CBCentralManager!, p: CBPeripheral?, wc: CBCharacteristic?, sent = false
    var count = 0, lastKey = ""

    override init() { super.init(); cm = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { print("bluetooth off"); exit(1) }
        print("[\(ts())] escaneando…")
        c.scanForPeripherals(withServices: [SVC], options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.p == nil { print("não achou"); exit(2) }
        }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard self.p == nil else { return }
        self.p = p; p.delegate = self; c.stopScan(); c.connect(p, options: nil)
        print("[\(ts())] conectando \(p.name ?? "?")…")
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([SVC]) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics([W, N], for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == W { wc = ch }
            if ch.uuid == N { p.setNotifyValue(true, for: ch) }
        }
        guard let wc = wc, !sent else { return }
        sent = true
        print("[\(ts())] -> music cmd: \(hex([UInt8](Data(pkt))))")
        p.writeValue(Data(pkt), for: wc, type: .withoutResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { self.finish() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value else { return }
        let d = [UInt8](v)
        count += 1
        // dedup: mesma carga consecutiva imprime só uma vez (mas mantém contagem)
        let key = hex(d)
        let mark = key == lastKey ? "   (igual ao anterior)" : ""
        print("[\(ts())] N#\(count) len=\(d.count): \(key)\(mark)")
        lastKey = key
    }

    func finish() {
        print("=== fim: \(count) notificações em \(dur)s (\(String(format: "%.1f", Double(count)/dur))/s) ===")
        exit(0)
    }
}

var s: Sniff? = Sniff()
dispatchMain()
