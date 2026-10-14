#!/usr/bin/env python3
"""Pretty-printer do bytecode Uascent com opcodes identificados."""
import importlib.util, sys
D = "/private/var/folders/l1/6ydlwrjn679cz0q1d1pzdmhc0000gn/T/opencode"
spec = importlib.util.spec_from_file_location("luawalk", D + "/luawalk.py")
lw = importlib.util.module_from_spec(spec); spec.loader.exec_module(lw)

def load(path):
    data = open(path, "rb").read()
    r = lw.Reader(data); r.o = 12
    r.b(); r.b(); r.b(); r.b(); r.b()
    r.i64(); r.f64(); r.b()
    return lw.load_proto(r, 4)

def find(p, want, path="main"):
    if path == want: return p
    for i, sp in enumerate(p.protos):
        q = find(sp, want, f"{path}/{i}")
        if q is not None: return q
    return None

OPS = {0:"MOVE",1:"LOADK",4:"LOADNIL",6:"GETTABUP",7:"GETTABLE",8:"SETTABUP",
       10:"SETTABLE",11:"NEWTABLE",13:"ADD",22:"BXOR",29:"CONCAT",36:"CALL",
       38:"RETURN",39:"FORLOOP",40:"FORPREP",44:"CLOSURE"}

def fmtc(c):
    t, v = c
    if t == "str":
        try: return '"%s"' % v.decode("utf-8")
        except: return repr(v)
    if t == "int" and 0 <= v <= 255: return f"{v}(0x{v:02x})"
    return str(v)

def dis(p):
    out = []
    for pc, w in enumerate(p.code):
        op = w & 0x3F; A = (w>>6)&0xFF; C = (w>>14)&0xFF
        k22 = (w>>22)&1; B = (w>>23)&0xFF; k31 = (w>>31)&1; Bx = (w>>14)&0x3FFFF
        nm = OPS.get(op, f"op{op}")
        K = lambda i: (fmtc(p.consts[i]) if i < len(p.consts) else f"?{i}")
        RK_C = (f"K({K(C)})" if k22 else f"R{C}")
        RK_B = (f"K({K(B)})" if k31 else f"R{B}")
        s = f"{pc:4d} {nm:9s}"
        if nm == "MOVE": s += f"R{A} := R{B}"
        elif nm == "LOADK": s += f"R{A} := {K(Bx)}"
        elif nm == "LOADNIL": s += f"R{A}..R{A+B} := nil"
        elif nm == "GETTABUP": s += f"R{A} := UP{B}[{RK_C}]"
        elif nm == "GETTABLE": s += f"R{A} := R{B}[{RK_C}]"
        elif nm == "SETTABUP": s += f"UP{A}[{RK_B}] := {RK_C}"
        elif nm == "SETTABLE": s += f"R{A}[{RK_B}] := {RK_C}"
        elif nm == "NEWTABLE": s += f"R{A} := {{}} B={B} C={C}"
        elif nm == "ADD": s += f"R{A} := R{B} + {RK_C}"
        elif nm == "BXOR": s += f"R{A} := R{B} ^ {RK_C}"
        elif nm == "CONCAT": s += f"R{A} := R{B}..R{C}"
        elif nm == "CALL": s += f"R{A} := R{A}(args R{A+1}..R{A+B-1}) rets={C or 'var'}"
        elif nm == "RETURN": s += f"return R{A}..R{A+B-2}" + ("" if B else " (var)")
        elif nm == "CLOSURE": s += f"R{A} := proto[{Bx}]"
        elif nm in ("FORPREP","FORLOOP"): s += f"A={A} sBx={Bx-131071 if nm=='FORLOOP' else ''}"
        else: s += f"A={A} B={B} C={C} k22={k22} k31={k31} Bx={Bx}"
        out.append(s)
    return out

if __name__ == "__main__":
    main = load("/Applications/UascentBLELight.app/Wrapper/UascentBLELight.app/ua_common.lua")
    for want in sys.argv[1:]:
        p = find(main, want)
        print(f"\n{'='*72}\n=== {want} params={p.numparams} stack={p.maxstacksize}")
        print(f"locals: {[(l[0] or b'?').decode() for l in p.locvars]}")
        print(f"consts: {[fmtc(c) for c in p.consts]}")
        print("\n".join(dis(p)))
