#!/usr/bin/env python3
"""Annotador de disassembly: resolve __objc_stubs (seletores) e cfstrings."""
import subprocess, struct, sys, re

BIN = "/Applications/UascentBLELight.app/Wrapper/UascentBLELight.app/UascentBLELight"
data = open(BIN, "rb").read()
out = subprocess.run(["otool", "-l", BIN], capture_output=True, text=True).stdout
sects = {}; cur = None
for line in out.splitlines():
    line = line.strip()
    if line.startswith("sectname"): cur = line.split()[1]
    elif line.startswith("addr ") and cur: sects.setdefault(cur, {})["addr"] = int(line.split()[1], 16)
    elif line.startswith("size ") and cur: sects[cur]["size"] = int(line.split()[1], 16)
    elif line.startswith("offset ") and cur: sects[cur]["off"] = int(line.split()[1])

def va2off(va):
    for s in sects.values():
        if s.get("addr", 1 << 62) <= va < s["addr"] + s.get("size", 0):
            return s["off"] + (va - s["addr"])
    return None

def read_cstr(va):
    o = va2off(va)
    if o is None: return None
    e = data.index(b"\0", o)
    return data[o:e].decode("utf-8", "replace")

def cfstring(va):
    fo = va2off(va)
    if fo is None: return None
    ptr, ln = struct.unpack_from("<QQ", data, fo + 16)
    o = va2off(ptr)
    if o is None: return None
    try: return data[o:o+ln].decode("utf-8", "replace")
    except: return repr(data[o:o+ln])

os_ = sects["__objc_stubs"]; selrefs = sects.get("__objc_selrefs")
stub_cache = {}
def stub(va):
    if va in stub_cache: return stub_cache[va]
    r = None
    if va == 0x10044aa14: r = "objc_retain"
    elif va == 0x10044aa08: r = "objc_release"
    elif va == 0x10044aa38: r = "objc_retainAutoreleasedReturnValue"
    elif va == 0x10044aa20: r = "objc_retainAutorelease"
    elif va == 0x10044aa918: r = "objc_autoreleaseReturnValue"
    elif va == 0x10044a8d0: r = "objc_alloc"
    elif va == 0x100449d0c: r = "NSLog"
    elif va == 0x10044a954: r = "objc_enumerationMutation"
    else:
        fo = os_["off"] + (va - os_["addr"])
        if 0 <= fo < len(data) - 16:
            a, l = struct.unpack_from("<II", data, fo)
            if (a & 0x9F000000) == 0x90000000:
                immhi = (a >> 5) & 0x7FFFF; immlo = (a >> 29) & 0x3
                imm = (immhi << 2) | immlo
                if imm & 0x100000: imm -= 0x200000
                tp = (va & ~0xFFF) + (imm << 12)
                if (l & 0xFFC00000) == 0xF9400000:
                    sr = tp + (((l >> 10) & 0xFFF) << 3)
                    fo2 = va2off(sr)
                    if fo2 is not None:
                        s = read_cstr(struct.unpack_from("<Q", data, fo2)[0])
                        if s: r = s
    stub_cache[va] = r or f"sub_{va:x}"
    return stub_cache[va]

if __name__ == "__main__":
    addr = int(sys.argv[1], 16)
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    dis = open("/Users/joao/Desktop/ulamp-alexa/disasm.txt").read().splitlines()
    start = None
    for i, l in enumerate(dis):
        m = re.match(r"^([0-9a-f]+)\t", l)
        if m:
            a = int(m.group(1), 16)
            if a == addr: start = i; break
    if start is None: sys.exit("endereço não encontrado")
    n = 0
    for l in dis[start:]:
        m = re.match(r"^([0-9a-f]+)\t(.*)$", l)
        if not m: continue
        a = int(m.group(1), 16); ins = m.group(2)
        annot = ""
        mb = re.match(r"bl\s+0x([0-9a-f]+)", ins)
        if mb:
            t = int(mb.group(1), 16)
            s = stub(t)
            annot = f"   ; {s}"
        ma = re.search(r"adrp\s+x\d+, (\d+) ; 0x([0-9a-f]+)", ins)
        nxt = dis[start + n + 1] if start + n + 1 < len(dis) else ""
        madd = re.match(r"add\s+x\d+, x\d+, #0x?([0-9a-f]+)", nxt.split("\t")[-1] if "\t" in nxt else "")
        if "cfstring ref" in l or "cfstring" in l:
            mm = re.search(r"0x([0-9a-f]+)", nxt) or re.search(r"#(0x[0-9a-f]+)", nxt)
            if ma:
                page = int(ma.group(2), 16)
                mo = re.search(r"#0x?([0-9a-f]+)", nxt)
                if mo:
                    offv = int(mo.group(1), 16)
                    s = cfstring(page + offv)
                    if s: annot += f"   ; CFSTR={s!r}"
        print(l + annot)
        n += 1
        if n >= count: break
