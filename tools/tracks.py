"""Tracks are data: a closed spline + width -> road ribbon, curbs, barriers, embankment, props, moving pieces.
Writes assets/tracks/track_N.glb (chunked kit) and tracks/track_N.json (what the game reads).

Frame per sample: t = tangent, r = t x up (horizontal right), up = world up (no banking: horizon never rolls).
Lateral offset x is along r; the drivable surface is |x| <= W + CURB."""
from __future__ import annotations
import math
import numpy as np
import trimesh
from scipy.spatial import cKDTree
from meshkit import Part, bake, export_glb, write_json, ROOT
import props
from palette import TRACKS, LIVERIES

DS = 2.0          # sample spacing (m)
CURB = 0.9        # curb strip outside the road edge (drivable)
WALL_H = 1.0
CHUNK = 400.0     # metres per kit chunk (culling + few draw calls)
MIN_R = 45.0      # tightest allowed curve radius
UP = np.array([0.0, 1.0, 0.0])


# ---------- spline ----------
def catmull_closed(pts: np.ndarray, per: int = 40) -> np.ndarray:
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        for t in np.linspace(0, 1, per, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return np.array(out)


def resample(dense: np.ndarray, ds: float) -> np.ndarray:
    seg = np.linalg.norm(np.diff(np.vstack([dense, dense[:1]]), axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    L = cum[-1]
    n = int(round(L / ds))
    ss = np.linspace(0, L, n, endpoint=False)
    loop = np.vstack([dense, dense[:1]])
    return np.stack([np.interp(ss, cum, loop[:, k]) for k in range(3)], axis=1), L * 1.0


class Track:
    def __init__(self, ctrl, ys, width):
        pts = np.array([[x, y, z] for (x, z), y in zip(ctrl, ys)], dtype=float)
        self.P, _ = resample(catmull_closed(pts), DS)
        n = len(self.P)
        self.n = n
        self.L = n * DS
        fwd = np.roll(self.P, -1, axis=0) - np.roll(self.P, 1, axis=0)
        self.T = fwd / np.linalg.norm(fwd, axis=1, keepdims=True)
        th = self.T * np.array([1, 0, 1])
        th /= np.linalg.norm(th, axis=1, keepdims=True)
        self.R = np.cross(th, UP)
        # signed curvature (+ = turning right), from heading change over 2 samples
        nxt, prv = np.roll(th, -1, axis=0), np.roll(th, 1, axis=0)
        self.K = np.einsum("ij,ij->i", nxt - prv, self.R) / (2 * DS)
        self.W = np.full(n, float(width))
        self.tree = cKDTree(self.P[:, [0, 2]])

    def at(self, s: float):
        i = int(round(s / DS)) % self.n
        return self.P[i], self.T[i], self.R[i], i

    def world(self, s: float, x: float, dy: float = 0.0) -> np.ndarray:
        p, _, r, _ = self.at(s)
        return p + r * x + UP * dy

    def clear_of_road(self, xz, radius: float, margin: float = 3.0) -> bool:
        d, i = self.tree.query(xz)
        return d > self.W[i] + CURB + WALL_H + margin + radius

    def chunk_of(self, xz) -> int:
        _, i = self.tree.query(xz)
        return int(i * DS // CHUNK)


# ---------- ribbon helpers ----------
def ribbon(tr: Track, i0: int, i1: int, x0, x1, y0=0.0, y1=0.0, closed_ok=True) -> trimesh.Trimesh:
    """Quad strip between lateral offsets x0..x1 (arrays or scalars per sample), heights y0..y1 above the centreline."""
    idx = [k % tr.n for k in range(i0, i1 + 1)]
    P, R = tr.P[idx], tr.R[idx]
    a = P + R * np.broadcast_to(x0, len(idx))[:, None] if np.ndim(x0) == 0 else P + R * np.asarray(x0)[idx][:, None]
    b = P + R * np.broadcast_to(x1, len(idx))[:, None] if np.ndim(x1) == 0 else P + R * np.asarray(x1)[idx][:, None]
    a = a + UP * y0
    b = b + UP * y1
    m = len(idx)
    v = np.vstack([a, b])
    f = []
    for k in range(m - 1):
        # winding so the face normal points up (or toward -x for vertical strips with x0 == x1)
        f += [[k, m + k, k + 1], [k + 1, m + k, m + k + 1]]
    mesh = trimesh.Trimesh(v, np.array(f), process=False)
    return mesh


def flip(m: trimesh.Trimesh) -> trimesh.Trimesh:
    m = m.copy()
    m.invert()
    return m


def up_facing(m: trimesh.Trimesh) -> trimesh.Trimesh:
    return m if m.face_normals[:, 1].mean() >= 0 else flip(m)


def dashes(tr: Track, i0, i1, x, every=9.0, length=3.0, width=0.16, dy=0.02):
    ms = []
    step = int(every / DS)
    for k in range(i0 - i0 % step, i1, step):
        if k < i0:
            continue
        kk = k + max(1, int(length / DS))
        ms.append(up_facing(ribbon(tr, k, min(kk, i1), x - width / 2, x + width / 2, dy, dy)))
    return ms


# ---------- placement ----------
def placed(m: trimesh.Trimesh, pos, face_dir) -> trimesh.Trimesh:
    """Copy of a local-space prop at pos, its local -Z turned to point along face_dir (horizontal)."""
    z = -np.asarray(face_dir, float)
    z[1] = 0
    z /= np.linalg.norm(z)
    x = np.cross(UP, z)
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = x, UP, z, pos
    c = m.copy()
    c.apply_transform(M)
    return c


class Kit:
    """Collects baked meshes per chunk."""

    def __init__(self, tr: Track):
        self.tr = tr
        self.chunks: dict[int, list[trimesh.Trimesh]] = {}

    def add(self, m: trimesh.Trimesh, chunk: int | None = None):
        if chunk is None:
            c = m.vertices.mean(axis=0)
            chunk = self.tr.chunk_of(c[[0, 2]])
        self.chunks.setdefault(chunk, []).append(m)

    def prop_side(self, m, s, side, off, radius, yaw_to_road=True):
        """Place prop at lateral offset side*off; returns False if it would touch any road."""
        tr = self.tr
        pos = tr.world(s, side * off)
        if not tr.clear_of_road(pos[[0, 2]], radius):
            return False
        p, t, r, _ = tr.at(s)
        self.add(placed(m, pos, -side * r if yaw_to_road else t))
        return True


def road(tr: Track, kit: Kit, pal, skip_ground=()):
    """Asphalt, lines, curbs, walls, embankment - per chunk."""
    per = int(CHUNK / DS)
    W = tr.W
    for c0 in range(0, tr.n, per):
        c1 = min(c0 + per, tr.n)  # one sample of overlap with the next chunk (ribbon closes the gap)
        ch = c0 // per
        parts = [Part(up_facing(ribbon(tr, c0, c1, -W, W)), pal["road"])]
        for x in (-4.5, 0.0, 4.5):
            parts += [Part(m, pal["line"], 1) for m in dashes(tr, c0, c1, x)]
        for sx in (-1, 1):
            parts.append(Part(up_facing(ribbon(tr, c0, c1, sx * (W - 0.45), sx * (W - 0.3), 0.02, 0.02)), pal["line"], 1))
            # curbs: alternating 4 m blocks
            blk = int(4 / DS)
            for k in range(c0, c1, blk):
                col = pal["curb"][(k // blk) % 2]
                parts.append(Part(up_facing(ribbon(tr, k, min(k + blk, c1), sx * W, sx * (W + CURB), 0.05, 0.05)), col))
            wx = W + CURB + 0.2
            parts.append(Part(up_facing(ribbon(tr, c0, c1, sx * wx, sx * (wx + 0.4), WALL_H, WALL_H)), pal["wall"]))
            inner = ribbon(tr, c0, c1, sx * wx, sx * wx, 0.0, WALL_H)
            outer = ribbon(tr, c0, c1, sx * (wx + 0.4), sx * (wx + 0.4), 0.0, WALL_H)
            # inner face looks at the road (-sx*r), outer face looks away
            parts.append(Part(_face_toward(inner, tr, c0, -sx), pal["wall"]))
            parts.append(Part(_face_toward(outer, tr, c0, sx), pal["wall"]))
            # gap between road and curb/wall base so no sky shows through
            parts.append(Part(up_facing(ribbon(tr, c0, c1, sx * (W + CURB), sx * wx, 0.0, 0.0)), pal["road"]))
            if ch not in skip_ground:
                parts.append(Part(up_facing(ribbon(tr, c0, c1, sx * (wx + 0.4), sx * (wx + 26), 0.0, -2.5)), pal["ground"]))
        kit.add(bake(parts), ch)


def _face_toward(m, tr, i, side):
    r = tr.R[i % tr.n]
    return m if (m.face_normals @ (side * r)).mean() >= 0 else flip(m)


def ground_plane(pal, y=-2.4, size=4000):
    v = np.array([[-size, y, -size], [size, y, -size], [size, y, size], [-size, y, size]], float)
    m = trimesh.Trimesh(v, [[0, 2, 1], [0, 3, 2]], process=False)
    return bake([Part(up_facing(m), pal["ground"], 1)])


def start_area(tr: Track, kit: Kit, pal, seed):
    W = tr.W[0]
    p, t, r, _ = tr.at(0.0)
    kit.add(placed(props.gantry(pal, 2 * (W + CURB + 0.6)), p, t), 0)
    kit.add(placed(props.checker_line(2 * W), p, t), 0)
    gs = props.grandstand(pal, 60, seed)
    for side in (-1, 1):
        kit.prop_side(gs, 40.0, side, W + 6.0, 4.0)


def scatter(tr: Track, kit: Kit, rng, maker, count, off_lo, off_hi, radius, tries=8, s_range=None):
    n = 0
    for _ in range(count * tries):
        if n >= count:
            break
        s = rng.uniform(*(s_range or (0, tr.L)))
        side = rng.choice([-1, 1])
        off = rng.uniform(off_lo, off_hi)
        if kit.prop_side(maker(), s, side, tr.W[0] + off, radius):
            n += 1
    return n


def billboards(tr, kit, pal, rng, n):
    for k in range(n):
        li = k % len(LIVERIES)
        bb = props.billboard(pal, LIVERIES[li][1], LIVERIES[li][2], 40 + k)
        for _ in range(10):
            if kit.prop_side(bb, rng.uniform(80, tr.L - 80), rng.choice([-1, 1]), tr.W[0] + rng.uniform(5, 9), 5.5):
                break


def lamps(tr, kit, pal, every=36.0):
    lp = props.lamp(pal)
    k = 0
    s = 10.0
    while s < tr.L:
        kit.prop_side(lp, s, 1 if k % 2 == 0 else -1, tr.W[0] + CURB + 1.2, 0.0)
        s += every / 2
        k += 1


# ---------- track definitions ----------
def track_1():
    """Night Harbor: city loop at dusk. Long harbour straight with a bridge over the water, docks with cranes,
    a railway crossing whose two arms take turns (one side always open)."""
    pal = TRACKS[1]
    ctrl = [(0, 150), (0, 0), (0, -250), (40, -390), (170, -440), (300, -410), (390, -300), (425, -150),
            (430, 50), (420, 200), (360, 310), (260, 350), (170, 330), (80, 330), (20, 280)]
    ys = [0, 0, 0, 0, 0, 0, 0, 2, 7, 2, 0, 0, 0, 0, 0]
    tr = Track(ctrl, ys, 9.0)
    rng = np.random.default_rng(1)
    kit = Kit(tr)
    # bridge: harbour straight (x > 400, z between -120 and 140) has water under it, no embankment
    bridge = [i for i in range(tr.n) if tr.P[i, 0] > 400 and -120 < tr.P[i, 2] < 140]
    road(tr, kit, pal, skip_ground={int(i * DS // CHUNK) for i in bridge} - {0})
    for i in bridge[::6]:  # pillars + railings glow posts
        p, t, r, _ = tr.at(i * DS)
        for sx in (-1, 1):
            pil = bake([props.P(props.bd.Pos(0, -6, 0) * props.bd.Box(1.2, 12 + p[1], 1.2), pal["metal"])])
            kit.add(placed(pil, p + r * sx * (tr.W[i] + 1.5), t))
    water = trimesh.Trimesh(np.array([[380, -2.0, -700], [1400, -2.0, -700], [1400, -2.0, 700], [380, -2.0, 700]]), [[0, 2, 1], [0, 3, 2]], process=False)
    kit.add(bake([Part(up_facing(water), pal["water"], 1)]), 99)
    start_area(tr, kit, pal, 3)
    lamps(tr, kit, pal)
    billboards(tr, kit, pal, rng, 6)
    # cranes along the dock (east of the bridge), facing the water
    cr = props.crane(pal)
    for z in (-260, -120, 40, 180):
        kit.add(placed(cr, np.array([520.0, -2.0, z]), np.array([1.0, 0, 0])), 98)
    # city blocks: towers behind the walls, never on any road
    blds = [props.building(pal, rng.uniform(12, 22), rng.uniform(12, 22), rng.uniform(18, 60), k, outline=0.12) for k in range(10)]
    placed_n = 0
    for _ in range(900):
        if placed_n >= 120:
            break
        s = rng.uniform(0, tr.L)
        side = rng.choice([-1, 1])
        p = tr.world(s, side * (tr.W[0] + rng.uniform(16, 70)))
        if p[0] > 380:  # harbour side stays open water
            continue
        if kit.prop_side(blds[int(rng.integers(len(blds)))], s, side, np.linalg.norm(p - tr.world(s, 0)), 15.0):
            placed_n += 1
    palms = [props.palm(pal, k) for k in range(4)]
    scatter(tr, kit, rng, lambda: palms[int(rng.integers(4))], 40, 4, 8, 2.0)
    gates_s = [0.62 * tr.L]
    data = {
        "name": "Night Harbor", "laps": 2, "music": "music_harbor", "fog": [120.0, 700.0],
        "gates": [{"s": round(gs, 1), "kind": "cross", "period": 6.0} for gs in gates_s],
        "slides": [],
        "birds": [{"s": round(s_, 1), "x": float(sx * 30), "y": 14.0} for s_, sx in ((300, 1), (900, -1), (1500, 1))],
        "traffic": 12,
    }
    return tr, kit, pal, data


def track_2():
    """Red Canyon: desert highway at sunset. Rolling hills, a tunnel through a butte, two sliding
    construction barriers that sweep across the lanes (always a gap on one side)."""
    pal = TRACKS[2]
    ctrl = [(0, 150), (0, -100), (-60, -300), (-200, -430), (-380, -420), (-490, -270), (-460, -80), (-530, 110),
            (-440, 290), (-290, 370), (-140, 330), (-30, 290)]
    ys = [0, 0, 8, 16, 18, 10, 4, 12, 20, 12, 4, 1]
    tr = Track(ctrl, ys, 9.0)
    rng = np.random.default_rng(2)
    kit = Kit(tr)
    road(tr, kit, pal)
    start_area(tr, kit, pal, 5)
    # tunnel: arch shell over the road through a butte; light strips on the ceiling
    t0, t1 = 0.40 * tr.L, 0.40 * tr.L + 140
    i0, i1 = int(t0 / DS), int(t1 / DS)
    arch = []
    R_ = tr.W[0] + CURB + 1.0
    seg = 9
    for k in range(seg):
        a0, a1 = math.pi * k / seg, math.pi * (k + 1) / seg
        x0, y0 = -R_ * math.cos(a0), 1.0 + R_ * 0.7 * math.sin(a0)
        x1, y1 = -R_ * math.cos(a1), 1.0 + R_ * 0.7 * math.sin(a1)
        inner = ribbon(tr, i0, i1, x0, x1, y0, y1)
        if (inner.face_normals[:, 1].mean()) > 0:  # inside faces must look down/in
            inner = flip(inner)
        arch.append(Part(inner, pal["rock"], 1))
        outer = ribbon(tr, i0, i1, x0 * 1.6, x1 * 1.6, y0 + 6, y1 + 6)
        arch.append(Part(up_facing(outer), pal["rock2"]))
    for i in range(i0, i1, 5):
        arch.append(Part(up_facing(ribbon(tr, i, i + 1, -1.0, 1.0, 1.0 + R_ * 0.7 - 0.3, 1.0 + R_ * 0.7 - 0.3)), pal["lamp"], 1, glow=True))
    kit.add(bake(arch, outline=0.0), int(t0 // CHUNK))
    for end, sgn in ((i0, 1), (i1, -1)):  # portal faces: a cliff wall around each mouth
        p, t, r, _ = tr.at(end * DS)
        face = bake([props.P(props.bd.Pos(sx * (R_ + 9), 7, 0) * props.bd.Box(18, 18, 3), pal["rock2"]) for sx in (-1, 1)]
                    + [props.P(props.bd.Pos(0, 1.0 + R_ * 0.7 + 4.5, 0) * props.bd.Box(2 * R_ + 2, 9, 3), pal["rock2"])], outline=0.2)
        kit.add(placed(face, p, t * sgn))
    lamps(tr, kit, pal, every=60.0)
    billboards(tr, kit, pal, rng, 5)
    mesas = [props.mesa(pal, k) for k in range(6)]
    scatter(tr, kit, rng, lambda: mesas[int(rng.integers(6))], 28, 45, 160, 28.0)
    cacti = [props.cactus(pal, k) for k in range(5)]
    scatter(tr, kit, rng, lambda: cacti[int(rng.integers(5))], 90, 4, 30, 1.5)
    rocks = [props.boulder(pal, k) for k in range(5)]
    scatter(tr, kit, rng, lambda: rocks[int(rng.integers(5))], 40, 5, 35, 3.0)
    data = {
        "name": "Red Canyon", "laps": 2, "music": "music_canyon", "fog": [150.0, 800.0],
        "gates": [],
        "slides": [{"s": round(0.22 * tr.L, 1), "width": 7.0, "amp": 5.5, "period": 5.0},
                   {"s": round(0.78 * tr.L, 1), "width": 7.0, "amp": 5.5, "period": 4.0}],
        "tunnel": [round(t0, 1), round(t1, 1)],
        "birds": [{"s": round(s_, 1), "x": float(sx * 40), "y": 22.0} for s_, sx in ((250, -1), (1000, 1), (1700, -1))],
        "traffic": 10,
    }
    return tr, kit, pal, data


DEFS = {1: track_1, 2: track_2}
TRACK_TRIS = 260_000


def build() -> list[dict]:
    out = []
    for n, fn in DEFS.items():
        tr, kit, pal, data = fn()
        # geometry checks: curvature and loop closure
        rmin = 1.0 / max(np.abs(tr.K).max(), 1e-6)
        assert rmin >= MIN_R, f"track {n}: curve radius {rmin:.0f} m < {MIN_R}"
        gap = np.linalg.norm(tr.P[0] - tr.P[-1])
        assert gap < DS * 1.5, f"track {n}: loop not closed ({gap:.1f} m)"
        kit.add(ground_plane(pal), 97)
        scene = trimesh.Scene()
        tris = 0
        for ch, ms in sorted(kit.chunks.items()):
            m = trimesh.util.concatenate(ms)
            scene.add_geometry(m, node_name=f"chunk_{ch}", geom_name=f"chunk_{ch}")
            tris += len(m.faces)
        path = ROOT / f"assets/tracks/track_{n}.glb"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(scene.export(file_type="glb"))
        data.update({
            "length": round(tr.L, 1), "ds": DS, "width": float(tr.W[0]), "curb": CURB, "palette": pal,
            # per sample: x, y, z, curvature (lateral frame is rebuilt in-engine from neighbours)
            "samples": [[round(float(a), 2) for a in (*tr.P[i], tr.K[i])] for i in range(tr.n)],
        })
        write_json(ROOT / f"tracks/track_{n}.json", data)
        props_m = {"gate_post": props.gate_post(pal), "gate_arm": props.gate_arm(tr.W[0] + CURB),
                   "slide_barrier": props.slide_barrier(7.0)}
        for k, m in props_m.items():
            export_glb(m, ROOT / f"assets/tracks/{k}_{n}.glb", k)
        out.append({"track": n, "length_m": round(tr.L), "min_radius_m": round(rmin), "tris": tris, "chunks": len(kit.chunks)})
    export_glb(props.bird(), ROOT / "assets/fx/bird.glb", "bird")
    export_glb(props.cone(), ROOT / "assets/fx/cone.glb", "cone")
    return out


if __name__ == "__main__":
    for r in build():
        print(r)
