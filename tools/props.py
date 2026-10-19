"""Roadside props in build123d. Each builder returns a baked, vertex-coloured trimesh in local space
(origin on the ground, +Y up, facing -Z = toward the road when placed), ready to be copied along the track."""
from __future__ import annotations
import math
import numpy as np
import build123d as bd
from meshkit import Part, bake, mesh
import web
from palette import BASE


def P(shape, ramp_, base=2, glow=False, tol=0.03, ang=0.5):
    return Part(mesh(shape, tol, ang), ramp_, base, glow)


def building(pal, w, d, h, seed, outline=0.0):
    """Tower with lit window bands; a few floors dark so no two towers look alike."""
    rng = np.random.default_rng(seed)
    body = pal["bld"][seed % len(pal["bld"])]
    parts = [P(bd.Pos(0, h / 2, 0) * bd.Box(w, h, d), body)]
    if rng.random() < 0.5:  # setback crown
        parts.append(P(bd.Pos(0, h + 2, 0) * bd.Box(w * 0.6, 4, d * 0.6), body))
    floors = int(h // 3.5)
    for f in range(1, floors):
        if rng.random() < 0.3:
            continue
        y = f * 3.5
        col = [pal["win"][int(rng.integers(len(pal["win"])))]] * 3
        # one strip per face per floor: four thin glowing slabs, just proud of the walls
        parts += [P(bd.Pos(0, y, -d / 2 - 0.05) * bd.Box(w * 0.86, 1.3, 0.1), col, 1, True),
                  P(bd.Pos(0, y, d / 2 + 0.05) * bd.Box(w * 0.86, 1.3, 0.1), col, 1, True),
                  P(bd.Pos(-w / 2 - 0.05, y, 0) * bd.Box(0.1, 1.3, d * 0.86), col, 1, True),
                  P(bd.Pos(w / 2 + 0.05, y, 0) * bd.Box(0.1, 1.3, d * 0.86), col, 1, True)]
    return bake(parts, outline=outline)


def lamp(pal):
    post = bd.Pos(0, 4, 0) * bd.Cylinder(0.12, 8, rotation=(90, 0, 0))
    arm = bd.Pos(0, 7.9, -1.1) * bd.Box(0.14, 0.14, 2.3)
    head = bd.Pos(0, 7.75, -2.1) * bd.Box(0.6, 0.25, 0.9)
    return bake([P(post, pal["metal"]), P(arm, pal["metal"]), P(head, pal["lamp"], 1, True)])


def palm(pal, seed):
    rng = np.random.default_rng(seed)
    parts = []
    h = rng.uniform(7, 10)
    lean = rng.uniform(-0.12, 0.12)
    for i in range(5):  # stacked trunk segments: slight curve, tapering
        y0 = i * h / 5
        parts.append(P(bd.Pos(lean * y0, y0 + h / 10, 0) * bd.Cylinder(0.32 - i * 0.04, h / 5 + 0.1, rotation=(90, 0, 0)), pal["trunk"]))
    top = (lean * h, h, 0)
    for k in range(7):  # drooping fronds: thin boxes tilted down
        a = k * 360 / 7 + rng.uniform(-15, 15)
        leaf = bd.Pos(*top) * bd.Rot(0, a, 0) * bd.Rot(0, 0, -28) * bd.Pos(1.6, 0, 0) * bd.Box(3.4, 0.08, 0.7)
        parts.append(P(leaf, pal["leaf"]))
    return bake(parts)


def crane(pal):
    """Harbour container crane: a big readable silhouette against the dusk sky."""
    m = pal["metal"]
    red = pal["curb"][0]
    parts = [P(bd.Pos(sx * 5, 12, sz * 4) * bd.Box(0.8, 24, 0.8), red) for sx in (-1, 1) for sz in (-1, 1)]
    parts += [P(bd.Pos(0, 24, 0) * bd.Box(11, 1.2, 9), red),
              P(bd.Pos(0, 26, -14) * bd.Box(2, 1.4, 44), red),
              P(bd.Pos(0, 31, 0) * bd.Box(1.2, 10, 1.2), m),
              P(bd.Pos(0, 25, -24) * bd.Box(1.6, 1.2, 2), m)]
    return bake(parts, outline=0.15)


def billboard(pal, liv_paint, liv_web, seed):
    """Two posts and a board printed with a web (the race's own logo), neon frame."""
    board_w, board_h, y0 = 10.0, 5.0, 5.0
    parts = [P(bd.Pos(sx * 3.5, y0 / 2, 0.3) * bd.Box(0.4, y0, 0.4), pal["metal"]) for sx in (-1, 1)]
    parts.append(P(bd.Pos(0, y0 + board_h / 2, 0) * bd.Box(board_w, board_h, 0.3), liv_paint))
    face = bd.Plane(origin=(0, y0 + board_h / 2, -0.16), x_dir=(1, 0, 0), z_dir=(0, 0, -1))
    segs = web.strands(spokes=8, rings=4, r=2.2, sag=0.2, seed=seed)
    parts.append(P(bd.extrude(web.sketch(segs, 0.12, face), 0.04), liv_web, 1, tol=0.01))
    neon = [pal["neon"][seed % len(pal["neon"])]] * 3
    parts += [P(bd.Pos(0, y0 + sy * (board_h / 2 + 0.1), 0) * bd.Box(board_w + 0.4, 0.2, 0.36), neon, 1, True) for sy in (-1, 1)]
    return bake(parts)


def gantry(pal, span):
    """Start/finish arch over the road: towers, beam, checker banner, start lights."""
    m = pal["metal"]
    parts = [P(bd.Pos(sx * (span / 2 + 0.6), 4.5, 0) * bd.Box(1.2, 9, 1.2), m) for sx in (-1, 1)]
    parts.append(P(bd.Pos(0, 8.6, 0) * bd.Box(span + 2.4, 1.0, 1.4), m))
    n = int(span // 1.0)
    for i in range(n):
        for j in range(2):
            col = ["#f4f2fa"] * 3 if (i + j) % 2 == 0 else ["#1d1b26"] * 3
            parts.append(P(bd.Pos(-span / 2 + (i + 0.5) * span / n, 7.6 - j * 0.7, -0.72) * bd.Box(span / n, 0.7, 0.06), col, 1, True))
    return bake(parts)


def checker_line(span, depth=1.6):
    """Start line painted on the road."""
    parts = []
    n = int(span // 0.8)
    for i in range(n):
        for j in range(2):
            col = ["#f4f2fa"] * 3 if (i + j) % 2 == 0 else ["#1d1b26"] * 3
            parts.append(P(bd.Pos(-span / 2 + (i + 0.5) * span / n, 0.03, (j - 0.5) * depth / 2) * bd.Box(span / n, 0.02, depth / 2), col, 1, True))
    return bake(parts)


def grandstand(pal, length, seed):
    """Stepped bleachers with a crowd of simple figures (rounded blocks in mixed colours)."""
    rng = np.random.default_rng(seed)
    parts = []
    for k in range(4):
        parts.append(P(bd.Pos(0, 0.5 + k * 0.8, 1.0 + k * 1.2) * bd.Box(length, 1.0 + k * 1.6, 1.2), pal["wall"]))
    shirts = [BASE["tail"], ["#4ff3ff"] * 3, ["#ffd23d"] * 3, ["#f4f2fa"] * 3, ["#b6ff4f"] * 3, ["#ff7a3d"] * 3]
    for k in range(4):
        for i in range(int(length // 1.1)):
            if rng.random() < 0.25:
                continue
            x = -length / 2 + 0.6 + i * 1.1 + rng.uniform(-0.15, 0.15)
            y = 1.0 + k * 1.6
            fig = bd.Pos(x, y + 0.55, 1.0 + k * 1.2) * bd.Box(0.6, 1.1, 0.45)
            head = bd.Pos(x, y + 1.35, 1.0 + k * 1.2) * bd.Box(0.4, 0.4, 0.4)
            parts += [P(fig, shirts[int(rng.integers(len(shirts)))], 2, True), P(head, ["#e8b896"] * 3, 2, True)]
    return bake(parts)


def mesa(pal, seed):
    """Desert butte: two tapered tiers of an irregular outline."""
    rng = np.random.default_rng(seed)
    pts = []
    n = 9
    r0 = rng.uniform(14, 26)
    for i in range(n):
        a = 2 * math.pi * i / n
        r = r0 * rng.uniform(0.7, 1.15)
        pts.append((r * math.cos(a), r * math.sin(a)))
    h1, h2 = rng.uniform(14, 28), rng.uniform(6, 14)

    def ring(y, k):
        return bd.Plane(origin=(0, y, 0), x_dir=(1, 0, 0), z_dir=(0, 1, 0)) * bd.Polygon(*[(x * k, z * k) for x, z in pts], align=None)
    t1 = bd.loft([ring(0, 1.0), ring(h1, 0.78)])  # loft, not tapered extrude: OCC's taper offset fails on irregular outlines
    t2 = bd.loft([ring(h1 - 0.5, 0.5), ring(h1 + h2, 0.38)])
    return bake([P(t1, pal["rock"], 2, tol=0.2), P(t2, pal["rock2"], 2, tol=0.2)], outline=0.25)


def cactus(pal, seed):
    rng = np.random.default_rng(seed)
    h = rng.uniform(3, 5.5)
    c = pal["cactus"]
    parts = [P(bd.Pos(0, h / 2, 0) * bd.Cylinder(0.35, h, rotation=(90, 0, 0)), c)]
    for sx in (-1, 1):
        if rng.random() < 0.8:
            y = rng.uniform(1.2, h * 0.6)
            parts += [P(bd.Pos(sx * 0.7, y, 0) * bd.Box(1.0, 0.45, 0.45), c),
                      P(bd.Pos(sx * 1.1, y + 0.8, 0) * bd.Cylinder(0.25, 1.8, rotation=(90, 0, 0)), c)]
    return bake(parts, outline=0.04)


def boulder(pal, seed):
    rng = np.random.default_rng(seed)
    s = bd.Sphere(1.0)
    s = bd.scale(s, by=(rng.uniform(1.5, 3), rng.uniform(1.0, 2), rng.uniform(1.5, 3)))
    return bake([P(bd.Pos(0, 0.6, 0) * s, pal["rock"], 2, tol=0.3, ang=1.0)], outline=0.08)


def cone():
    c = bd.Pos(0, 0.4, 0) * bd.Cone(0.3, 0.06, 0.8, rotation=(-90, 0, 0))
    base = bd.Pos(0, 0.04, 0) * bd.Box(0.7, 0.08, 0.7)
    stripe = bd.Pos(0, 0.45, 0) * bd.Cylinder(0.18, 0.12, rotation=(90, 0, 0))
    return bake([P(c, ["#ff7a3d"] * 3, 1, True), P(base, ["#ff7a3d"] * 3, 1, True), P(stripe, ["#f4f2fa"] * 3, 1, True)])


# ---------- moving pieces (own .glb each; the game moves them) ----------
def gate_post(pal):
    """Railway-crossing post with flashing lamps (lamps are glow, blinked in-engine via material)."""
    m = pal["metal"]
    parts = [P(bd.Pos(0, 1.6, 0) * bd.Box(0.5, 3.2, 0.5), m), P(bd.Pos(0, 3.0, 0) * bd.Box(1.4, 0.5, 0.3), m)]
    parts += [P(bd.Pos(sx * 0.45, 3.0, -0.2) * bd.Cylinder(0.18, 0.12), BASE["tail"], 1, True) for sx in (-1, 1)]
    return bake(parts, outline=0.04)


def gate_arm(length):
    """Boom arm along +X from the pivot (origin), red/white stripes. Rotated about Z by the game."""
    parts = []
    n = int(length // 1.2)
    for i in range(n):
        col = BASE["tail"] if i % 2 == 0 else ["#f4f2fa"] * 3
        parts.append(P(bd.Pos((i + 0.5) * length / n, 0, 0) * bd.Box(length / n, 0.35, 0.2), col, 1, True))
    return bake(parts)


def slide_barrier(width):
    """Construction barrier block, chevron stripes; slides sideways across lanes in-engine."""
    parts = [P(bd.Pos(0, 0.55, 0) * bd.Box(width, 1.1, 0.8), ["#f4f2fa"] * 3, 1, True)]
    n = int(width // 1.0)
    for i in range(n):
        if i % 2 == 0:
            parts.append(P(bd.Pos(-width / 2 + (i + 0.5) * width / n, 0.55, -0.42) * bd.Box(width / n, 1.1, 0.04), ["#ff7a3d"] * 3, 1, True))
    parts += [P(bd.Pos(sx * (width / 2 - 0.2), 1.25, 0) * bd.Cylinder(0.14, 0.12, rotation=(90, 0, 0)), BASE["blink"], 1, True) for sx in (-1, 1)]
    return bake(parts)


def bird():
    body = bd.scale(bd.Sphere(0.25), by=(0.7, 0.6, 1.6))
    wings = [bd.Pos(sx * 0.55, 0.05, 0) * bd.Rot(0, 0, sx * 12) * bd.Box(1.0, 0.04, 0.35) for sx in (-1, 1)]
    return bake([P(body, ["#2b2840"] * 3, 1, True)] + [P(w, ["#2b2840"] * 3, 1, True) for w in wings])


# ---------- track 3 / 4 props ----------
def neon_sign(pal, seed):
    """Tall vertical sign on a pole: dark panel, glowing frame, three glowing bars (wordless)."""
    rng = np.random.default_rng(seed)
    neon = [pal["neon"][seed % len(pal["neon"])]] * 3
    h = rng.uniform(9, 14)
    parts = [P(bd.Pos(0, h / 2, 0.4) * bd.Box(0.4, h, 0.4), pal["metal"]),
             P(bd.Pos(0, h - 3, 0) * bd.Box(2.6, 6, 0.4), pal["bld"][0])]
    parts += [P(bd.Pos(sx * 1.35, h - 3, -0.05) * bd.Box(0.16, 6.2, 0.5), neon, 1, True) for sx in (-1, 1)]
    for k in range(3):
        col = [pal["neon"][(seed + k + 1) % len(pal["neon"])]] * 3
        parts.append(P(bd.Pos(0, h - 1.2 - k * 1.8, -0.22) * bd.Box(rng.uniform(1.2, 2.2), 0.6, 0.06), col, 1, True))
    return bake(parts, outline=0.05)


def lowcone(r, h, y0):
    """Cone standing on y0. Tessellate it coarsely (P(..., tol=0.5, ang=1.3)) for ~40 triangles.
    Note OCC caches a shape's first triangulation, so a fresh shape is needed per tolerance."""
    return bd.Pos(0, y0, 0) * bd.Cone(r, r * 0.04, h, rotation=(-90, 0, 0), align=(bd.Align.CENTER, bd.Align.CENTER, bd.Align.MIN))


def pine(pal, seed):
    """Stacked faceted cones with snow on the tip of each tier."""
    rng = np.random.default_rng(seed)
    h = rng.uniform(6, 11)
    parts = [P(bd.Pos(0, h * 0.12, 0) * bd.Box(0.5, h * 0.25, 0.5), pal["trunk"])]
    for k in range(3):
        r = (1.0 - k * 0.28) * h * 0.28
        y0 = h * (0.18 + k * 0.24)
        parts.append(P(lowcone(r, h * 0.38, y0), pal["leaf"], tol=0.5, ang=1.3))
        parts.append(P(lowcone(r * 0.5, h * 0.19, y0 + h * 0.19 + 0.02), pal["snow"], tol=0.5, ang=1.3))
    return bake(parts, outline=0.05)


def peak(pal, seed):
    """Distant mountain: lofted irregular base up to a narrow top, snow cap on the upper third."""
    rng = np.random.default_rng(seed)
    n = 8
    r0 = rng.uniform(60, 110)
    pts = [(r0 * rng.uniform(0.75, 1.1) * math.cos(2 * math.pi * i / n), r0 * rng.uniform(0.75, 1.1) * math.sin(2 * math.pi * i / n)) for i in range(n)]
    h = rng.uniform(70, 130)

    def ring(y, k, dx=0.0):
        return bd.Plane(origin=(dx, y, 0), x_dir=(1, 0, 0), z_dir=(0, 1, 0)) * bd.Polygon(*[(x * k, z * k) for x, z in pts], align=None)
    lean = rng.uniform(-10, 10)
    rock = bd.loft([ring(0, 1.0), ring(h * 0.62, 0.38, lean * 0.6), ring(h, 0.06, lean)], ruled=True)
    snow = rock & (bd.Pos(0, h * 0.62 + 50, 0) * bd.Box(500, 100, 500))
    rock = rock - (bd.Pos(0, h * 0.62 + 50, 0) * bd.Box(500, 100, 500))
    return bake([P(rock, pal["rock"], 2, tol=0.5, ang=1.0), P(snow, pal["snow"], 2, tol=0.5, ang=1.0)], outline=0.4)
