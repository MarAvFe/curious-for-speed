"""Cars in build123d: body = side profile ∩ top outline (visual hull), filleted; tapered greenhouse; wheels in arches.
Liveries are spider webs wrapped onto the paint (tools/web.py). Origin = ground under the car's centre, nose at -Z."""
from __future__ import annotations
import math
import build123d as bd
from meshkit import Part, bake, mesh, export_glb, ROOT
import web
from palette import BASE, LIVERIES, TRAFFIC

# Plane helpers. SIDE: local (u, v) = (-Z, Y), so side profiles are written nose-left as (forward, up).
# TOP: local (u, v) = (X, -Z), so top outlines are written as (right, forward).
SIDE = bd.Plane(origin=(0, 0, 0), x_dir=(0, 0, -1), z_dir=(1, 0, 0))
TOP = bd.Plane(origin=(0, 0, 0), x_dir=(1, 0, 0), z_dir=(0, 1, 0))


def side_prism(pts, width):
    return bd.extrude(SIDE * bd.Polygon(*pts, align=None), width / 2, both=True)


def top_prism(pts, y0, h, taper=0.0):
    return bd.extrude(bd.Plane(origin=(0, y0, 0), x_dir=(1, 0, 0), z_dir=(0, 1, 0)) * bd.Polygon(*pts, align=None), -h, taper=taper)


def wheel_at(x, z, r, w):
    return bd.Pos(x, r, z) * bd.Rot(0, 90, 0) * bd.Cylinder(r, w)


# --- models: forward = +u in SIDE, so the nose is at u = +L/2 ---
MODELS = {
    "stinger": {  # low wedge
        "side": [(2.25, 0.24), (2.3, 0.5), (2.0, 0.66), (0.6, 0.8), (-1.6, 0.86), (-2.2, 0.9), (-2.28, 0.6), (-2.2, 0.24)],
        "top": [(-0.72, 2.3), (0.72, 2.3), (0.94, 1.5), (0.94, -1.95), (0.86, -2.25), (-0.86, -2.25), (-0.94, -1.95), (-0.94, 1.5)],
        "cabin": [(0.75, 0.74), (-0.1, 1.2), (-0.95, 1.2), (-1.75, 0.82), (-1.75, 0.7), (0.75, 0.7)],
        "cabin_top": [(-0.78, 0.9), (0.78, 0.9), (0.78, -1.85), (-0.78, -1.85)],
        "wheel": (0.85, 1.38, -1.4, 0.33), "spoiler": True, "width": 1.88,
    },
    "brute": {  # tall muscle
        "side": [(2.3, 0.3), (2.32, 0.72), (2.1, 0.8), (0.9, 0.86), (-1.9, 0.9), (-2.28, 0.92), (-2.32, 0.6), (-2.25, 0.3)],
        "top": [(-0.86, 2.32), (0.86, 2.32), (0.98, 2.0), (0.98, -2.1), (0.9, -2.32), (-0.9, -2.32), (-0.98, -2.1), (-0.98, 2.0)],
        "cabin": [(0.55, 0.84), (-0.2, 1.36), (-1.1, 1.36), (-1.65, 0.9), (-1.65, 0.8), (0.55, 0.8)],
        "cabin_top": [(-0.85, 0.7), (0.85, 0.7), (0.85, -1.75), (-0.85, -1.75)],
        "wheel": (0.88, 1.45, -1.42, 0.36), "spoiler": False, "width": 1.96,
    },
    # civilian traffic: taller, boxier, slower-looking; never webbed
    "hatch": {
        "side": [(1.9, 0.32), (1.92, 0.7), (1.5, 0.84), (-1.8, 0.92), (-1.92, 0.8), (-1.9, 0.32)],
        "top": [(-0.8, 1.92), (0.8, 1.92), (0.86, 1.6), (0.86, -1.9), (-0.86, -1.9), (-0.86, 1.6)],
        "cabin": [(1.2, 0.84), (0.5, 1.5), (-1.6, 1.52), (-1.85, 0.9), (-1.85, 0.8), (1.2, 0.8)],
        "cabin_top": [(-0.8, 1.3), (0.8, 1.3), (0.8, -1.85), (-0.8, -1.85)],
        "wheel": (0.78, 1.2, -1.25, 0.32), "spoiler": False, "width": 1.74,
    },
    "van": {
        "side": [(2.4, 0.36), (2.45, 0.9), (2.0, 1.05), (-2.4, 1.1), (-2.45, 0.36)],
        "top": [(-0.95, 2.45), (0.95, 2.45), (1.0, 2.1), (1.0, -2.45), (-1.0, -2.45), (-1.0, 2.1)],
        "cabin": [(2.0, 1.0), (1.3, 1.95), (-2.4, 2.0), (-2.4, 0.95), (2.0, 0.95)],
        "cabin_top": [(-0.95, 2.1), (0.95, 2.1), (0.95, -2.4), (-0.95, -2.4)],
        "wheel": (0.86, 1.6, -1.6, 0.36), "spoiler": False, "width": 2.0, "taper": 4,
    },
    "pickup": {
        "side": [(2.5, 0.4), (2.55, 0.95), (1.4, 1.1), (-2.5, 1.12), (-2.55, 0.4)],
        "top": [(-0.98, 2.55), (0.98, 2.55), (1.02, 2.2), (1.02, -2.55), (-1.02, -2.55), (-1.02, 2.2)],
        "cabin": [(1.4, 1.08), (0.8, 1.85), (-0.7, 1.88), (-0.8, 1.05), (1.4, 1.05)],
        "cabin_top": [(-0.95, 1.3), (0.95, 1.3), (0.95, -0.8), (-0.95, -0.8)],
        "wheel": (0.9, 1.7, -1.6, 0.4), "spoiler": False, "width": 2.04, "taper": 6,
    },
}


def build_car(model: str):
    """Returns dict of build123d parts: body, glass, tyres, rims, lights_f, lights_r, trim."""
    M = MODELS[model]
    W = M["width"]
    body = side_prism(M["side"], W) & top_prism(M["top"], 0.0, 1.2)
    try:
        body = bd.fillet(body.edges().filter_by(bd.Axis.Z, reverse=True), 0.06)
    except Exception:
        pass
    wx, zf, zr, r = M["wheel"]
    for z in (zf, zr):
        body = body - bd.Pos(0, r, z) * bd.Rot(0, 90, 0) * bd.Cylinder(r + 0.04, W + 0.4)
    glass = side_prism(M["cabin"], W) & top_prism(M["cabin_top"], 0.65, 1.4, taper=M.get("taper", 18))
    # roof panel is paint (and carries web), the rest of the greenhouse is window
    roof_y = max(p[1] for p in M["cabin"]) - 0.05
    roofbox = bd.Pos(0, roof_y + 0.5, 0) * bd.Box(4, 1, 6)
    body = body + (glass & roofbox)
    glass = glass - roofbox
    tyres = [wheel_at(sx * wx, z, r, 0.28) for sx in (-1, 1) for z in (zf, zr)]
    rims = [wheel_at(sx * (wx + 0.03), z, r * 0.6, 0.26) for sx in (-1, 1) for z in (zf, zr)]
    zn = max(p[1] for p in M["top"])
    zb = min(p[1] for p in M["top"])
    un = max(q[0] for q in M["side"])
    ylf = [p for p in M["side"] if p[0] > un - 0.35]
    yl = sum(p[1] for p in ylf) / len(ylf) + 0.04
    lights_f = [bd.Pos(sx * 0.62, yl, -zn + 0.02) * bd.Box(0.36, 0.1, 0.1) for sx in (-1, 1)]
    lights_r = [bd.Pos(sx * 0.6, 0.72, -zb - 0.02) * bd.Box(0.44, 0.1, 0.1) for sx in (-1, 1)]
    trim = []
    if M["spoiler"]:
        trim.append(bd.Pos(0, 1.06, 1.95) * bd.Box(1.7, 0.06, 0.32))
        trim += [bd.Pos(sx * 0.6, 0.96, 1.95) * bd.Box(0.06, 0.18, 0.2) for sx in (-1, 1)]
    return {"body": body, "glass": glass, "tyres": tyres, "rims": rims, "lights_f": lights_f, "lights_r": lights_r,
            "trim": trim, "M": M}


def livery(parts, style: int):
    """Web strands on hood (+ roof) and both doors. style picks the web shape so cars differ."""
    body, M = parts["body"], parts["M"]
    W = M["width"]
    out = []
    # hood: web centred near the nose, seen from above; only on surfaces above the beltline
    segs = web.strands(spokes=8 + style, rings=4, r=1.3, sag=0.2, seed=11 + style)
    top_sk = web.sketch(segs, 0.06, TOP, centre=(0.0, 1.2 - 0.5 * style), scale=(1.0, 1.25))
    keep_top = bd.Pos(0, 1.3, 0) * bd.Box(W - 0.2, 1.6, 6)  # inset: no stretched strands down the flanks
    w1 = web.wrap(body, top_sk, 3.0, keep=keep_top)
    if w1:
        out.append(w1)
    # doors: a corner fan web from the rear wheel arch, seen from the side; below the window line
    segs = web.strands(spokes=5, rings=3, r=1.5, sag=0.22, seed=21 + style, spread=math.pi * 0.75, a0=-0.15)
    side_sk = web.sketch(segs, 0.06, SIDE, centre=(-0.9 + 0.3 * style, 0.2))
    keep_side = bd.Pos(0, 0.45, 0) * bd.Box(W + 1, 0.6, 6) - bd.Box(W - 0.3, 3, 6)
    w2 = web.wrap(body, side_sk, W, keep=keep_side)
    if w2:
        out.append(w2)
    # the chase camera shows the BACK of the player's car all race: trunk lid + rear panel get webs too
    zb = min(p[1] for p in M["top"])  # TOP v = forward, so the rear is the most negative v
    segs = web.strands(spokes=7, rings=3, r=1.0, sag=0.2, seed=31 + style)
    trunk_sk = web.sketch(segs, 0.06, TOP, centre=(0.0, zb + 0.3), scale=(1.0, 0.8))
    w3 = web.wrap(body, trunk_sk, 3.0, keep=bd.Pos(0, 1.3, -zb - 0.9) * bd.Box(W - 0.2, 1.6, 1.8))
    if w3:
        out.append(w3)
    BACK = bd.Plane(origin=(0, 0, 0), x_dir=(1, 0, 0), z_dir=(0, 0, 1))  # local (u, v) = (X, Y), seen from behind
    segs = web.strands(spokes=8, rings=3, r=0.9, sag=0.2, seed=41 + style, spread=math.pi, a0=math.pi)
    back_sk = web.sketch(segs, 0.06, BACK, centre=(0.0, 0.85), scale=(1.1, 0.65))
    w4 = web.wrap(body, back_sk, 6.0, keep=bd.Pos(0, 0.6, -zb - 0.2) * bd.Box(W + 1, 1.2, 0.8))
    if w4:
        out.append(w4)
    return out


def _parts(p, paint, web_ramp, webs, blink=False):
    parts = [Part(mesh(p["body"], 0.01, 0.4), paint)] + [Part(mesh(w, 0.012, 0.6), web_ramp, 1, glow=True) for w in webs]  # glow=True: no outline shell (sits on the outlined body)
    parts += [Part(mesh(p["glass"]), BASE["glass"], 1)]
    parts += [Part(mesh(x, 0.02, 0.5), BASE["tyre"], 1) for x in p["tyres"]] + [Part(mesh(x, 0.02, 0.5), BASE["rim"]) for x in p["rims"]]
    parts += [Part(mesh(x), BASE["head"], 1, glow=True) for x in p["lights_f"]]
    parts += [Part(mesh(x), BASE["tail"], 1, glow=True) for x in p["lights_r"]]
    parts += [Part(mesh(x), web_ramp if webs else BASE["chrome"]) for x in p["trim"]]
    return parts


def _blinkers(p):
    """Separate node `blink`: four amber corner lights, toggled in-engine for lane changes / hazard."""
    M = p["M"]
    zn = max(q[1] for q in M["top"])
    zb = min(q[1] for q in M["top"])
    hw = M["width"] / 2 - 0.05
    ms = [mesh(bd.Pos(sx * hw, 0.62, z) * bd.Box(0.12, 0.1, 0.18)) for sx in (-1, 1) for z in (-zn + 0.12, -zb - 0.12)]
    return bake([Part(m, BASE["blink"], 1, glow=True) for m in ms])


BUDGET = 14_000


def build() -> list[dict]:
    out = []
    for model in ("stinger", "brute"):
        p = build_car(model)
        webs = {k: livery(p, k) for k in range(3)}  # web shape depends on style only; colours reuse it
        for i, (name, paint, wr) in enumerate(LIVERIES):
            m = bake(_parts(p, paint, wr, webs[i % 3]), outline=0.02)
            r = export_glb(m, ROOT / f"assets/cars/car_{model}_{i}.glb", "car")
            out.append(dict(r, name=f"car_{model}_{i}", budget=BUDGET))
    for model in ("hatch", "van", "pickup"):
        p = build_car(model)
        bl = _blinkers(p)
        for i, paint in enumerate(TRAFFIC):
            m = bake(_parts(p, paint, None, []), outline=0.02)
            r = export_glb(m, ROOT / f"assets/cars/traffic_{model}_{i}.glb", "car", extra={"blink": bl})
            out.append(dict(r, name=f"traffic_{model}_{i}", budget=5_000))
    return out


if __name__ == "__main__":
    for r in build():
        print(r)
