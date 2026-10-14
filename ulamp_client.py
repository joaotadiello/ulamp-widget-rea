#!/usr/bin/env python3
"""uLamp (Uascent) BLE client de referência — implementação fiel aos builders Lua.

Requer: pip install bleak   (macOS: Python 3.11+ recomendado)
Uso:
  python3 ulamp_client.py scan              # procura a lâmpada e lista serviços
  python3 ulamp_client.py on [MAC]          # liga
  python3 ulamp_client.py off [MAC]         # desliga
  python3 ulamp_client.py bright 80 [MAC]   # brilho
  python3 ulamp_client.py color FF8000 [MAC]# cor RGB
  python3 ulamp_client.py temp 4500 [MAC]   # temperatura de cor (K)
  python3 ulamp_client.py scene 1 [MAC]     # cena predefinida
  python3 ulamp_client.py status [MAC]      # consulta estado

Transporte (inferido, padrão Telink): serviço FFB0, write FFB1, notify FFB2.
UUID completos: 0000XXXX-0000-1000-8000-00805F9B34FB.
"""

import asyncio, sys, struct

from bleak import BleakClient, BleakScanner

SVC_TELINK = "0000ffb0-0000-1000-8000-00805f9b34fb"
CHR_WRITE = "0000ffb1-0000-1000-8000-00805f9b34fb"
CHR_NOTIFY = "0000ffb2-0000-1000-8000-00805f9b34fb"

HDR = b"\x4a\x58"  # 'J', 'X'

class Tid:
    """Transaction ID rotativo 0-255 (igual ao TID global do Lua)."""
    def __init__(self): self.v = 0
    def next(self):
        v = self.v; self.v = (self.v + 1) & 0xFF; return v

_tid = Tid()

def xor_checksum(data: bytes) -> int:
    """XorValue: XOR de todos os bytes (seed 0x4A embutida no cabeçalho)."""
    x = 0
    for b in data: x ^= b
    return x

def packet(op1: int, op2: int, args: bytes = b"", flags: int = 0x00) -> bytes:
    """Monta pacote completo: 4a 58 <tid> <op1> <op2> <flags> <args...> <xor>."""
    body = HDR + bytes([_tid.next(), op1, op2, flags]) + args
    return body + bytes([xor_checksum(body)])

# ---- builders (espelham o bytecode ua_common.lua) -------------------------

def p_power(on: bool)      -> bytes: return packet(0x02, 0x82, bytes([1 if on else 0]))
def p_bright(v: int)       -> bytes: return packet(0x4C, 0x82, bytes([v & 0xFF]))
def p_speed(v: int)        -> bytes: return packet(0x60, 0x82, bytes([v & 0xFF]))
def p_saturation(v: int)   -> bytes: return packet(0x21, 0x82, bytes([v & 0xFF]))
def p_scene(scene_id: int) -> bytes: return packet(0x42, 0x82, bytes([scene_id & 0xFF]))
def p_rgb(r, g, b)         -> bytes: return packet(0x32, 0x82, bytes([r & 0xFF, g & 0xFF, b & 0xFF]))
def p_color_temp(kelvin: int) -> bytes:
    # ControlColorTemperature: Convert2ByteValue -> 2 bytes big-endian
    return packet(0x64, 0x82, struct.pack(">H", kelvin))
def p_lamp_beads(n: int)   -> bytes: return packet(0xF0, 0x82, struct.pack(">H", n))
def p_linkage(st: int)     -> bytes: return packet(0x2D, 0x82, bytes([st & 0xFF]))
def p_dynamic(dyn_id)      -> bytes: return packet(0x43, 0x82, bytes([dyn_id & 0xFF]))
def p_music(music_id)      -> bytes: return packet(0x44, 0x82, bytes([music_id & 0xFF]))
def p_static(sid)          -> bytes: return packet(0x45, 0x82, bytes([sid & 0xFF]))
def p_get_status()         -> bytes: return packet(0xD0, 0x82)
def p_get_product_id()     -> bytes: return packet(0xE1, 0x82)
def p_get_device_id()      -> bytes: return packet(0xD0, 0x82)
def p_sync_time(ts: int)   -> bytes: return packet(0xC0, 0x82, struct.pack(">I", ts))
def p_get_timer_list()     -> bytes: return packet(0xA3, 0x82)
def p_delete_timer(tid)    -> bytes: return packet(0xA0, 0x82, bytes([tid & 0xFF]))
def p_delete_scene()       -> bytes: return packet(0x13, 0x82)

# ---- parser de notificações ------------------------------------------------

RESP_FIELDS = {
    0x8204: "estado rápido: power/brightness/speed/scene/color",
    0x824F: "estado completo",
    0x82B0: "deviceId", 0x82B1: "productId", 0x82C1: "ack timestamp",
    0x82A3: "lista de timers", 0x8261: "timer/countdown",
    0x8212: "ack deletar cena", 0x8213: "ack deletar countdown",
    0x8234: "cor de cena", 0x82F1: "segmento de pacote longo",
}

def on_notify(sender, data: bytes):
    print(f"\n<< notificação ({len(data)}B): {data.hex(' ')}")
    if data[:2] != HDR:
        print("   (sem enquadramento JX — pode ser PDU mesh Telink cru)")
        return
    x = xor_checksum(data[:-1])
    ok = "OK" if x == data[-1] else f"FALHOU (esperado {x:02x})"
    print(f"   JX tid={data[2]:02x} op={data[3]:02x} {data[4]:02x} flags={data[5]:02x} xor={data[-1]:02x} [{ok}]")
    op16 = data[3] | (data[4] << 8)
    if op16 in RESP_FIELDS: print(f"   -> {RESP_FIELDS[op16]}")
    print(f"   payload: {data[6:-1].hex(' ')}")

# ---- CLI --------------------------------------------------------------------

async def find_lamp(timeout=8.0):
    print(f"escaneando {timeout}s por dispositivos com serviço FFB0 / nomes iLamp|uLamp|Uascent...")
    devices = await BleakScanner.discover(timeout=timeout, return_adv=True)
    cands = []
    for d, adv in devices.values():
        uuids = [str(u).upper() for u in (adv.service_uuids or [])]
        if any("FFB0" in u for u in uuids) or any(k in (d.name or "").upper() for k in ("ILAMP", "ULAMP", "UASCENT")):
            cands.append((d, adv))
            print(f"  candidato: {d.name} [{d.address}] svc={uuids} mfr={ (adv.manufacturer_data or {}).keys() }")
    if not cands:
        print("  nenhum candidato; mostre todos:")
        for d, adv in devices.values():
            print(f"  {str(d.name):30s} {d.address}  svc={[str(u)[:8] for u in (adv.service_uuids or [])]}")
        return None
    return cands[0][0]

async def run(cmd, arg, mac=None):
    if mac is None:
        dev = await find_lamp()
        if not dev: sys.exit("lâmpada não encontrada")
        mac = dev.address
    async with BleakClient(mac) as client:
        print(f"conectado a {mac}; serviços:")
        for s in client.services:
            print(f"  serviço {s.uuid} " + " ".join(f"[{c.uuid[:8]} props={','.join(c.properties)}]" for c in s.characteristics))
        try:
            await client.start_notify(CHR_NOTIFY, on_notify)
        except Exception as e:
            print(f"(notify em {CHR_NOTIFY[:8]} falhou: {e})")
        pk = {
            "on": lambda: p_power(True), "off": lambda: p_power(False),
            "bright": lambda: p_bright(int(arg)), "speed": lambda: p_speed(int(arg)),
            "sat": lambda: p_saturation(int(arg)), "scene": lambda: p_scene(int(arg)),
            "color": lambda: p_rgb(int(arg[0:2],16), int(arg[2:4],16), int(arg[4:6],16)),
            "temp": lambda: p_color_temp(int(arg)), "beads": lambda: p_lamp_beads(int(arg)),
            "linkage": lambda: p_linkage(int(arg)), "dynamic": lambda: p_dynamic(int(arg)),
            "music": lambda: p_music(int(arg)), "static": lambda: p_static(int(arg)),
            "status": p_get_status, "product": p_get_product_id, "device": p_get_device_id,
            "timers": p_get_timer_list, "delscene": p_delete_scene,
            "synctime": lambda: p_sync_time(int(__import__("time").time())),
        }[cmd]()
        print(f">> write {CHR_WRITE[:8]}: {pk.hex(' ')}")
        await client.write_gatt_char(CHR_WRITE, pk, response=False)
        await asyncio.sleep(3.0)  # escuta notificações

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] == "scan":
        asyncio.run(find_lamp(10.0))
    else:
        cmd = sys.argv[1]; arg = sys.argv[2] if len(sys.argv) > 2 else "0"
        mac = sys.argv[3] if len(sys.argv) > 3 else None
        asyncio.run(run(cmd, arg, mac))
