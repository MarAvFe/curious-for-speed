"""Geometry + palette toolkit: build123d solids -> trimesh -> flat-shaded vertex-colour .glb.

Conventions: 1 unit = 1 m, forward = -Z, up = +Y. Colours named FAMILY+DIGIT, dark->light.
"""
from __future__ import annotations
import colorsys, json, math
from pathlib import Path
import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parent.parent
KEY_LIGHT = np.array([-0.45, 0.8, 0.4])  # from upper-left-behind (camera looks -Z)
KEY_LIGHT = KEY_LIGHT / np.linalg.norm(KEY_LIGHT)

# ---------- palette ----------
COOL_HUE, WARM_HUE = 255.0, 45.0


def _toward(h: float, target: float, amt: float) -> float:
    d = ((target - h + 540) % 360) - 180
    return (h + d * amt) % 360


def ramp(hue: float, sat: float, lo: float = 0.30, hi: float = 0.86, n: int = 5) -> list[str]:
    """Hue-shifted pastel ramp: shadows cooler/purpler, highlights warmer."""
    out = []
    for i in range(n):
        f = i / (n - 1)
        h = _toward(hue, COOL_HUE, (1 - f) * 0.22) if f < 0.5 else _toward(hue, WARM_HUE, (f - 0.5) * 0.25)
        l = lo + (hi - lo) * f
        s = sat * (0.85 + 0.3 * math.sin(math.pi * f))  # ends a bit greyer
        r, g, b = colorsys.hls_to_rgb(h / 360, l, min(s, 1))
        out.append("#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255)))
    return out


def hex_rgb(c: str) -> tuple[float, float, float]:
    return tuple(int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))


# ---------- build123d -> trimesh ----------
def mesh(shape, tol: float = 0.01, ang: float = 0.3) -> trimesh.Trimesh:
    """Tessellate a build123d Shape (Solid/Compound/Part) into a trimesh. Coarse tolerances keep it low-poly."""
    try:
        v, f = shape.tessellate(tol, ang)
    except AttributeError:  # a degenerate sliver face (thin booleans) won't triangulate: mesh face by face, skip it
        v, f = [], []
        for face in shape.faces():
            try:
                fv, ff = face.tessellate(tol, ang)
            except AttributeError:
                continue
            f += [[a + len(v), b + len(v), c + len(v)] for a, b, c in ff]
            v += fv
    return trimesh.Trimesh(np.array([(p.X, p.Y, p.Z) for p in v]), np.array(f), process=True)


def place(m: trimesh.Trimesh, pos=(0, 0, 0), rot_deg=(0, 0, 0), scale=1.0) -> trimesh.Trimesh:
    m = m.copy()
    if np.isscalar(scale):
        m.apply_scale(scale)
    else:
        m.apply_transform(np.diag([*scale, 1.0]))
    rx, ry, rz = (math.radians(a) for a in rot_deg)
    m.apply_transform(trimesh.transformations.euler_matrix(rx, ry, rz, "sxyz"))
    m.apply_translation(pos)
    return m


# ---------- colour bake ----------
class Part:
    """A mesh plus the colour ramp it is painted with."""

    def __init__(self, mesh: trimesh.Trimesh, ramp_: list[str], base: int = 2, glow: bool = False):
        self.mesh, self.ramp, self.base, self.glow = mesh, ramp_, base, glow


def outline_shell(m: trimesh.Trimesh, width: float) -> trimesh.Trimesh:
    """Inverted hull: welded copy pushed out along smooth normals, winding flipped (renders as a rim)."""
    w = trimesh.Trimesh(m.vertices.copy(), m.faces.copy(), process=True)  # weld so normals are smooth
    w.vertices = w.vertices + w.vertex_normals * width
    w.invert()
    return w


def darkest(ramp_: list[str]) -> str:
    r, g, b = hex_rgb(ramp_[0])
    return "#%02x%02x%02x" % tuple(round(c * 255 * 0.7) for c in (r, g, b))


def bake(parts: list[Part], glow_points: list[tuple[np.ndarray, float]] = (), outline: float = 0.0) -> trimesh.Trimesh:
    """Flat-shade: per-face ramp step from facing vs key light, +1 step near glow sources.
    outline > 0 adds an inverted-hull rim per non-glow part, in the darkest colour of that part's ramp."""
    if outline > 0:
        parts = parts + [Part(outline_shell(p.mesh, outline), [darkest(p.ramp)] * 3, 1, glow=True)
                         for p in parts if not p.glow]
    verts, faces, cols = [], [], []
    off = 0
    for p in parts:
        m = p.mesh
        tri = m.vertices[m.faces]  # (F,3,3)
        n = m.face_normals
        d = n @ KEY_LIGHT
        step = np.where(d > 0.55, 1, np.where(d < -0.15, -1, 0))
        idx = np.clip(p.base + step, 0, len(p.ramp) - 1)
        if glow_points and not p.glow:
            c = tri.mean(axis=1)
            for gp, rad in glow_points:
                near = np.linalg.norm(c - gp, axis=1) < rad
                idx = np.where(near, np.minimum(idx + 1, len(p.ramp) - 1), idx)
        rgb = np.array([hex_rgb(p.ramp[i]) for i in idx])
        verts.append(tri.reshape(-1, 3))
        faces.append(np.arange(len(m.faces) * 3).reshape(-1, 3) + off)
        cols.append(np.repeat(rgb, 3, axis=0))
        off += len(m.faces) * 3
    v, f, c = np.vstack(verts), np.vstack(faces), np.vstack(cols)
    out = trimesh.Trimesh(v, f, process=False)
    rgba = np.hstack([c, np.ones((len(c), 1))])
    out.visual = trimesh.visual.ColorVisuals(out, vertex_colors=(rgba * 255).astype(np.uint8))
    return out


def export_glb(mesh: trimesh.Trimesh, path: Path, name: str, extra: dict | None = None) -> dict:
    """Write the render mesh, plus optional extra named meshes (nodes the game animates, e.g. `blink`).
    No collision meshes: the game collides analytically (track distance + lateral offset)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    scene = trimesh.Scene()
    scene.add_geometry(mesh, node_name=name, geom_name=name)
    tris = len(mesh.faces)
    for k, m in (extra or {}).items():
        scene.add_geometry(m, node_name=k, geom_name=k)
        tris += len(m.faces)
    path.write_bytes(scene.export(file_type="glb"))
    return {"name": name, "tris": int(tris)}


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1))
