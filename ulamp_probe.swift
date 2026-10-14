// ulamp_probe.swift — sonda todas as características: onde o JX funciona?
import Foundation
import CoreBluetooth

let HDR: [UInt8] = [0x4A, 0x58]
func pk(_ tid: UInt8, _ op1: UInt8, _ op2: UInt8, _ args: [UInt8]) -> [UInt8] {
    var b: [UInt8] = HDR + [tid, op1, op2, 0x00] + args
    var x: UInt8 = 0; for c in b { x ^= c }
    b.append(x); return b
}

class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var cm: CBCentralManager!
    var target: CBPeripheral!
    var notified: [CBUUID: Int] = [:]
    var writes: [(CBCharacteristic, [UInt8], String)] = []
    
    override init() { super.init(); cm = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { print("ERRO BT \(c.state.rawValue)"); exit(1) }
        print("[i] escaneando..."); c.scanForPeripherals(withServices: [CBUUID(string: "FFB0")], options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { self.die("não achou") }
    }
    func die(_ m: String) -> Never { print("[fim] \(m) — notificações recebidas: \(notified)"); exit(0) }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("[+] \(p.name ?? "?") rssi=\(RSSI)")
        target = p; p.delegate = self; c.stopScan(); c.connect(p, options: nil)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        print("[i] conectado; serviços..."); p.discoverServices(nil)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        // pronto quando todos os serviços tiverem características
        for s in p.services ?? [] where s.characteristics == nil { return }
        print("[i] mapa GATT completo:")
        for s in p.services ?? [] {
            for ch in s.characteristics ?? [] {
                print("    \(s.uuid.uuidString) / \(ch.uuid.uuidString) — props=\(ch.properties.rawValue)")
                if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                    p.setNotifyValue(true, for: ch)
                }
            }
        }
        // escreve o query de status em todas as chars de write
        var t: UInt8 = 0
        for s in p.services ?? [] {
            for ch in s.characteristics ?? [] where ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                let data = pk(t, 0xD0, 0x82, []); t += 1
                let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                print(">> write \(ch.uuid.uuidString): \(hex)")
                p.writeValue(Data(data), for: ch, type: ch.properties.contains(.write) ? .withResponse : .withoutResponse)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.die("escuta encerrada") }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value else { return }
        notified[ch.uuid, default: 0] += 1
        let hex = d.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("<< \(ch.uuid.uuidString): \(hex)")
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        print("[w] ack write \(ch.uuid.uuidString): \(error?.localizedDescription ?? "ok")")
    }
}

let app = Probe()
var keeper: Probe? = app
dispatchMain()
