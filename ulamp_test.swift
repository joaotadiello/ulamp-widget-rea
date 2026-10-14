// ulamp_test.swift — validação ao vivo do protocolo uLamp (Uascent/Telink BLE)
// Uso: ulamp_test scan | ulamp_test <cmd> [arg] [mac]
//   cmd: on off bright color temp scene status product

import Foundation
import CoreBluetooth

let FFB0 = CBUUID(string: "FFB0")
let FFB1 = CBUUID(string: "FFB1")
let FFB2 = CBUUID(string: "FFB2")

var tid: UInt8 = 0
func nextTid() -> UInt8 { let t = tid; tid = (tid + 1) & 0xFF; return t }

func packet(_ cmd: UInt8, _ args: [UInt8]) -> [UInt8] {
    // protocolo produto 88006190: 0A A5 <TID> <cmd> <args...> (sem checksum)
    return [0x0A, 0xA5, nextTid(), cmd] + args
}

func buildPacket(_ cmd: String, _ arg: String) -> [UInt8]? {
    switch cmd {
    case "on":      return packet(0x01, [1])
    case "off":     return packet(0x01, [0])
    case "mode":    return packet(0x02, [UInt8(arg) ?? 1])
    case "status":  return packet(0xFF, [])
    case "color":
        guard arg.count == 6, let r = UInt8(arg.prefix(2), radix: 16),
              let g = UInt8(arg.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(arg.suffix(2), radix: 16) else { return nil }
        // paintColor: 04 <type=1> <action=1> <count=1> <brightness> <r> <g> <b>
        return packet(0x04, [1, 1, 1, 100, r, g, b])
    case "rainbow":
        // 5 cores em 5 segmentos? vermelho amarelo verde ciano azul
        var args: [UInt8] = [1, 1, 5]
        for c in ["ff0000","ffd400","00e64d","00e5ff","0066ff"] {
            args += [100, UInt8(c.prefix(2),radix:16)!, UInt8(c.dropFirst(2).prefix(2),radix:16)!, UInt8(c.suffix(2),radix:16)!]
        }
        return packet(0x04, args)
    case "white":
        guard let v = UInt8(arg) else { return nil }
        return packet(0x0B, [v, v, v])
    case "beads":
        guard let n = UInt16(arg) else { return nil }
        return packet(0x07, [UInt8(n & 0xFF), UInt8(n >> 8), 0xFF, 0xFF])
    default: return nil
    }
}

let respNames: [UInt16: String] = [
    0x8204: "estado rápido (power/brightness/speed/scene/color)",
    0x824F: "estado completo", 0x8212: "ack del cena", 0x8213: "ack del countdown",
    0x8222: "saturação", 0x8225: "enhancement", 0x822B: "sensitivity", 0x822E: "linkage",
    0x8234: "cor de cena", 0x8243: "dynamic", 0x8244: "music", 0x8245: "static",
    0x8261: "timer", 0x8266: "countdown", 0x82A3: "lista timers",
    0x82B0: "deviceId", 0x82B1: "productId", 0x82C1: "ack timestamp",
    0x82E0: "evento mesh", 0x82E1: "evento mesh", 0x82F1: "segmento longo",
]

class Central: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var cm: CBCentralManager!
    let mode: String, arg: String, wantMac: String?
    var target: CBPeripheral?
    var writeChar: CBCharacteristic?
    var notifyChar: CBCharacteristic?
    var started = Date()
    var done = false
    var sent = false

    init(mode: String, arg: String, mac: String?) {
        self.mode = mode; self.arg = arg; self.wantMac = mac
        super.init()
        cm = CBCentralManager(delegate: self, queue: nil)
    }

    func fail(_ msg: String) -> Never { print("ERRO: \(msg)"); exit(1) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { fail("Bluetooth \(c.state.rawValue) — ligue o BT") }
        print("[i] Bluetooth OK — escaneando 10s...")
        c.scanForPeripherals(withServices: [FFB0], options: nil)
        c.scanForPeripherals(withServices: nil, options: nil)  // também sem filtro p/ ver todos
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if self.target == nil {
                print("[!] nenhum candidato FFB0/iLamp; listando tudo que aparece...\n(dica: abra o app uLamp para a lâmpada acordar)")
                self.fail("lâmpada não encontrada")
            }
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "")
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let hasFFB0 = uuids.contains(FFB0)
        let named = name.uppercased().contains("ILAMP") || name.uppercased().contains("ULAMP") || name.uppercased().contains("UASCENT")
        guard hasFFB0 || named else { return }
        print("[+] candidato: \(name) [\(p.identifier.uuidString)] FFB0=\(hasFFB0) RSSI=\(RSSI)")
        if target == nil && (wantMac == nil || p.identifier.uuidString == wantMac) {
            target = p
            p.delegate = self
            c.stopScan()
            print("[i] conectando...")
            c.connect(p, options: nil)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        print("[i] conectado — descobrindo serviços...")
        p.discoverServices(nil)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            let chars = (s.characteristics ?? []).map { "\($0.uuid.uuidString)[\(String(describing: $0.properties))]" }
            print("    serviço \(s.uuid.uuidString): \(chars.isEmpty ? "(explorando...)" : chars.joined(separator: " "))")
            if s.characteristics == nil { p.discoverCharacteristics(nil, for: s) }
            if s.uuid == FFB0 {
                for ch in s.characteristics ?? [] {
                    if ch.uuid == FFB1 { writeChar = ch }
                    if ch.uuid == FFB2 { notifyChar = ch }
                }
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        // re-avalia FFB1/FFB2 e lista
        for s in p.services ?? [] {
            let chars = (s.characteristics ?? []).map { $0.uuid.uuidString }
            print("    serviço \(s.uuid.uuidString): \(chars.joined(separator: " "))")
        }
        for ch in s.characteristics ?? [] {
            if s.uuid == FFB0 && ch.uuid == FFB1 { writeChar = ch }
            if s.uuid == FFB0 && ch.uuid == FFB2 { notifyChar = ch }
        }
        guard writeChar != nil else {
            print("[!] serviço FFB0 sem FFB1 — tentando primeira característica write de qualquer serviço")
            for s in p.services ?? [] { for ch in s.characteristics ?? [] where ch.properties.contains(.write) {
                print("    fallback write: \(s.uuid)/\(ch.uuid)"); writeChar = ch } }
            guard writeChar != nil else { fail("nenhuma característica de escrita") }
            return send()
        }
        send()
    }

    func send() {
        guard !sent else { return }
        sent = true
        let p = target!
        if let nc = notifyChar {
            p.setNotifyValue(true, for: nc)
            print("[i] inscrito em FFB2 (notify)")
        } else { print("[i] FFB2 não encontrada — sem escuta") }
        if mode == "scan" {
            print("[i] modo scan: nada a enviar; aguardando notificações 5s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
            return
        }
        guard let pk = buildPacket(mode, arg) else { fail("comando inválido: \(mode) \(arg)") }
        let hex = pk.map { String(format: "%02x", $0) }.joined(separator: " ")
        print(">> write FFB1: \(hex)")
        p.writeValue(Data(pk), for: writeChar!, type: .withoutResponse)
        // status query emite também d0 82 para forçar resposta
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            print("[i] fim da escuta"); exit(0)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value else { return }
        let hex = d.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("<< notificação: \(hex)")
        let bytes = [UInt8](d)
        guard bytes.count >= 7, bytes[0] == 0x4A, bytes[1] == 0x58 else {
            print("   (sem framing JX — PDU cru/Telink mesh)"); return
        }
        var x: UInt8 = 0; for b in bytes.dropLast() { x ^= b }
        let op16 = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)
        print("   JX tid=\(String(format: "%02x", bytes[2])) op=\(String(format: "%04x", op16)) flags=\(String(format: "%02x", bytes[5])) xor=\(bytes.last! == x ? "OK" : "FALHOU") payload=\(bytes.dropFirst(6).dropLast().map { String(format: "%02x", $0) }.joined(separator: " "))")
        if let n = respNames[op16] { print("   -> \(n)") }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let e = error { print("[!] notify erro: \(e.localizedDescription)") }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        if !done { fail("desconectado: \(error?.localizedDescription ?? "?")") }
    }
}

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "scan"
let arg  = args.count > 2 ? args[2] : "0"
let mac  = args.count > 3 ? args[3] : nil
setbuf(stdout, nil)
print("[i] uLamp live test — modo: \(mode) \(arg)")
var keeper: Central? = Central(mode: mode, arg: arg, mac: mac)
dispatchMain()
