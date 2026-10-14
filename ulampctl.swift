// ulampctl — cliente uLamp (produto 88006190) para Home Assistant / CLI
// Protocolo validado ao vivo: 0A A5 <TID> <CMD> <ARGS...> — sem checksum, sem auth.
// Serviço FFB0, write FFB1, notify FFB2.
//
// Uso: ulampctl <cmd> [arg]
//   on | off | status | mode <n> | color RRGGBB [brilho] | white <0-255>
//   scene <id 1-?> | music <sens> | beads <n> <total> | style <1-6> | keepalive
// Saída: última linha = JSON de estado (para Home Assistant).

import Foundation
import CoreBluetooth

let SVC = CBUUID(string: "FFB0"), W = CBUUID(string: "FFB1"), N = CBUUID(string: "FFB2")

var tid: UInt8 = UInt8.random(in: 0...255)
func pk(_ cmd: UInt8, _ args: [UInt8] = []) -> [UInt8] { [0x0A, 0xA5, tid, cmd] + args }

func hex2rgb(_ s: String) -> [UInt8]? {
    guard s.count == 6, let r = UInt8(s.prefix(2), radix: 16),
          let g = UInt8(s.dropFirst(2).prefix(2), radix: 16),
          let b = UInt8(s.suffix(2), radix: 16) else { return nil }
    return [r, g, b]
}

func build(_ cmd: String, _ a: [String]) -> [UInt8]? {
    let arg = a.first ?? ""
    switch cmd {
    case "on":     return pk(0x01, [1])
    case "off":    return pk(0x01, [0])
    case "mode":   return pk(0x02, [UInt8(arg) ?? 0])
    case "color":
        guard let rgb = hex2rgb(arg) else { return nil }
        let bri = a.count > 1 ? (UInt8(a[1]) ?? 100) : 100
        return pk(0x04, [1, 1, 1, bri, rgb[0], rgb[1], rgb[2]])   // paintColor full set
    case "white":  return pk(0x0B, [UInt8(arg) ?? 255, UInt8(arg) ?? 255, UInt8(arg) ?? 255])
    case "scene":  return pk(0x01, [1]) // cena predefinida via power+mode; placeholder
    case "beads":
        guard let n = UInt16(a[0]), let t = a.count > 1 ? UInt16(a[1]) : UInt16(150) else { return nil }
        return pk(0x07, [UInt8(n & 0xFF), UInt8(n >> 8), UInt8(t & 0xFF), UInt8(t >> 8)])
    case "style":  return pk(0x09, [UInt8(arg) ?? 1])
    case "status": return pk(0xFF)
    default: return nil
    }
}

// ---- parser de estado (espelha BleRecieveDataResolv do 88006190.lua) ----
var state: [String: Any] = [:]
var segs: [Int] = []
func parse(_ d: [UInt8]) {
    guard d.count >= 5, d[0] == 0x0A, d[1] == 0xA5 else { return }
    let op = d[3]
    switch op {
    case 0x01: state["power"] = d[4]
    case 0x02: state["mode"] = d[4]
    case 0x07:
        if d.count >= 10 { state["lamp_bead"] = Int(d[4]) | (Int(d[5]) << 8)
                           state["total_lamp_bead"] = Int(d[6]) | (Int(d[7]) << 8) }
    case 0x09: state["lineStyle"] = d[4]
    case 0x0B: state["whiteBalance"] = [d[4], d[5], d[6]]
    case 0x0C: if d.count >= 7 { segs.append(Int(d[4])) }
    case 0x05:
        if d.count >= 8 {
            state["scene_changeMode"] = d[5]; state["scene_speed"] = d[6]
            state["scene_brightness"] = d[7]
        }
    default: break
    }
}

class Ctl: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var cm: CBCentralManager!, p: CBPeripheral?, wc: CBCharacteristic?, sent = false
    let data: [UInt8], listen: Double
    init(_ d: [UInt8], _ l: Double) { data = d; listen = l; super.init(); cm = CBCentralManager(delegate: self, queue: nil) }
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { print("{\"error\":\"bt:\(c.state.rawValue)\"}"); exit(1) }
        c.scanForPeripherals(withServices: [SVC], options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.finish("not_found") }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard self.p == nil else { return }
        self.p = p; p.delegate = self; c.stopScan(); c.connect(p, options: nil)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([SVC]) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics([W, N], for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard !sent else { return }
        for ch in s.characteristics ?? [] {
            if ch.uuid == W { wc = ch }
            if ch.uuid == N { p.setNotifyValue(true, for: ch) }
        }
        guard let wc = wc else { return }
        sent = true
        p.writeValue(Data(data), for: wc, type: .withoutResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + listen) { self.finish("ok") }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value else { return }
        parse([UInt8](v))
    }
    func finish(_ code: String) {
        if !segs.isEmpty { state["segments"] = segs }
        if let jsonData = try? JSONSerialization.data(withJSONObject: state, options: .sortedKeys),
           let js = String(data: jsonData, encoding: .utf8) { print(js) }
        else { print("{}") }
        exit(code == "ok" ? 0 : 2)
    }
}

let args = CommandLine.arguments
guard args.count > 1, let pkt = build(args[1], Array(args.dropFirst(2))) else {
    print("uso: ulampctl on|off|status|mode <n>|color RRGGBB [bri]|white <v>|beads <n> <tot>|style <n>")
    exit(64)
}
setbuf(stdout, nil)
let listenSec = args[1] == "status" ? 2.5 : 0.6
var keeper: Ctl? = Ctl(pkt, listenSec)
dispatchMain()
