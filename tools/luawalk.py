#!/usr/bin/env python3
"""Lua 5.3 bytecode structure walker for Uascent custom VM (shuffled opcodes).
Parses proto tree + constants; skips instruction decoding."""
import struct, sys

class Proto:
    pass

class Reader:
    def __init__(self, data): self.d = data; self.o = 0
    def b(self): v = self.d[self.o]; self.o += 1; return v
    def i32(self): v = struct.unpack_from("<i", self.d, self.o)[0]; self.o += 4; return v
    def u32(self): v = struct.unpack_from("<I", self.d, self.o)[0]; self.o += 4; return v
    def i64(self): v = struct.unpack_from("<q", self.d, self.o)[0]; self.o += 8; return v
    def f64(self): v = struct.unpack_from("<d", self.d, self.o)[0]; self.o += 8; return v
    def st(self, sz):  # size_t of given byte width
        if sz == 4: return self.u32()
        return struct.unpack_from("<Q", self.d, self.o)[0] if sz == 8 else self.b()
    def string(self, tsz):
        n = self.b()
        if n == 0: return None
        if n == 0xFF:
            n = self.st(tsz)
            if n == 0: return None
        s = self.d[self.o:self.o+n-1]; self.o += n-1; return s

def load_proto(r, tsz):
    p = Proto()
    p.source = r.string(tsz)
    p.linedefined = r.i32(); p.lastlinedefined = r.i32()
    p.numparams = r.b(); p.is_vararg = r.b(); p.maxstacksize = r.b()
    n = r.i32(); p.code = [r.u32() for _ in range(n)]
    n = r.i32(); p.consts = []
    for _ in range(n):
        t = r.b()
        if t in (0x00,): p.consts.append(("nil", None))
        elif t == 0x01: p.consts.append(("bool", bool(r.b())))
        elif t == 0x02: p.consts.append(("flt", r.f64()))
        elif t == 0x03: p.consts.append(("int", r.i64()))
        elif t in (0x04, 0x05): p.consts.append(("str", r.string(tsz)))
        elif t == 0x12: p.consts.append(("int32", r.i32()))
        elif t == 0x13: p.consts.append(("int", r.i64()))
        elif t == 0x14: p.consts.append(("str", r.string(tsz)))
        else: raise ValueError(f"const type {t:#x} at offset {r.o-1:#x}")
    n = r.i32(); p.upvals = [(r.b(), r.b()) for _ in range(n)]
    n = r.i32(); p.protos = [load_proto(r, tsz) for _ in range(n)]
    n = r.i32(); p.lineinfo = [r.i32() for _ in range(n)]
    n = r.i32(); p.locvars = [(r.string(tsz), r.i32(), r.i32()) for _ in range(n)]
    n = r.i32(); p.upvalnames = [r.string(tsz) for _ in range(n)]
    return p

def walk(p, path, out):
    out.append(f"\n{'='*78}\nFUNC {path}  line={p.linedefined}..{p.lastlinedefined} params={p.numparams} vararg={p.is_vararg} stack={p.maxstacksize} ncode={len(p.code)}")
    if p.upvalnames:
        out.append("  upvals: " + ", ".join((u or b"?").decode("utf-8","replace") for u in p.upvalnames))
    if p.locvars:
        out.append("  locals: " + ", ".join((lv[0] or b"?").decode("utf-8","replace") for lv in p.locvars))
    strs = [c for c in p.consts if c[0] == "str"]
    if strs:
        out.append("  const strings:")
        for _, sv in strs:
            try:
                t = sv.decode("utf-8")
                out.append(f'    "{t}"' if t.isprintable() or "\x00" in t else f"    {sv!r}")
            except: out.append(f"    {sv!r}")
    nums = [c for c in p.consts if c[0] in ("int","flt") and c[1] not in (0,1,2)]
    if nums: out.append("  const nums: " + ", ".join(str(v) for _, v in nums[:80]))
    bools = [c for c in p.consts if c[0] == "bool"]
    if bools: out.append("  const bools: " + ", ".join(str(v) for _, v in bools[:20]))
    for i, sp in enumerate(p.protos):
        walk(sp, f"{path}/{i}", out)

if __name__ == "__main__":
    data = open(sys.argv[1], "rb").read()
    assert data[:4] == b"\x1bLua" and data[4] == 0x53
    r = Reader(data)
    r.o = 6  # sig+ver+format
    lucac_data = r.b  # LUAC_DATA 6 bytes
    r.o = 12
    sz_int = r.b(); sz_size_t = r.b(); sz_inst = r.b(); sz_intg = r.b(); sz_num = r.b()
    luac_int = r.i64() if sz_intg == 8 else r.i32()
    luac_num = r.f64()
    nupv = r.b()
    main = load_proto(r, sz_size_t)
    out = [f"# parsed OK; consumed {r.o} of {len(data)} bytes; trailing={len(data)-r.o}",
           f"# sizes int={sz_int} size_t={sz_size_t} inst={sz_inst} integer={sz_intg} number={sz_num} main-upvals={nupv}"]
    walk(main, "main", out)
    print("\n".join(out))
