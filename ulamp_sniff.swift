// ulamp_sniff.swift — scanner passivo: dumpa advertisements enquanto o app oficial controla a lampada
import Foundation
import CoreBluetooth

class Sniff: NSObject, CBCentralManagerDelegate {
    var cm: CBCentralManager!
    var seen: [UUID: (name: String, n: Int)] = [:]
    var interesting = 0
    let start = Date()

    override init() { super.init(); cm = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { print("ERRO BT \(c.state.rawValue)"); exit(1) }
        print("[i] sniffing 75s — CONTROLE A LAMPADA PELO APP IPHONE AGORA")
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        DispatchQueue.main.asyncAfter(deadline: .now() + 75) {
            print("[fim] pacotes 'interessantes' (mudancas de manufacturer data): \(self.interesting)")
            exit(0)
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let mfr = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let svc = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let name = p.name ?? "?"
        let prev = seen[p.identifier]
        // so imprime quando: novo dispositivo, ou mfr mudou (filtro de duplicatas variaveis)
        let key = mfr?.hexString ?? "-"
        guard prev == nil || (prev!.n < 3) || (mfr != nil && RSSI.intValue > -55) else { return }
        seen[p.identifier] = (name, (prev?.n ?? 0) + 1)
        let mk = mfr != nil ? mfr!.hexString : ""
        let sd = svc != nil ? svc!.map { "\($0.key.uuidString.prefix(8))=\($0.value.hexString)" }.joined(separator: " ") : ""
        if name.lowercased().hasPrefix("uac") {
            let t = Date().timeIntervalSince(start)
            print(String(format: "[%7.2fs] %@", t, mk))
            interesting += 1
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

let s = Sniff()
var keeper: Sniff? = s
dispatchMain()
