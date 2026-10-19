"""Spider-web liveries in build123d: a 2D web of thin strands, pushed through the car and kept only where it
meets a thin skin just outside the body, so the strands hug every curve of the paint."""
from __future__ import annotations
import math
import numpy as np
import build123d as bd


def strands(spokes: int = 9, rings: int = 5, r: float = 1.1, sag: float = 0.18, seed: int = 0,
            spread: float = 2 * math.pi, a0: float = 0.0) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    """Web as 2D segments around (0,0): radial spokes + sagging threads between neighbouring spokes.
    spread < 2*pi gives a corner web (fan). Fixed seed -> identical rebuilds."""
    rng = np.random.default_rng(seed)
    n = spokes if spread >= 2 * math.pi - 1e-6 else spokes - 1
    ang = [a0 + spread * i / (spokes if n == spokes else spokes - 1) + rng.uniform(-0.12, 0.12) for i in range(spokes)]
    segs = [((0.0, 0.0), (r * math.cos(a), r * math.sin(a))) for a in ang]
    for k in range(1, rings + 1):
        rk = r * (k / rings) ** 0.9 * rng.uniform(0.92, 1.0)
        for i in range(n):
            a, b = ang[i], ang[(i + 1) % spokes]
            if b < a:
                b += 2 * math.pi
            p = (rk * math.cos(a), rk * math.sin(a))
            q = (rk * math.cos(b), rk * math.sin(b))
            m = (a + b) / 2
            mid = (rk * (1 - sag) * math.cos(m), rk * (1 - sag) * math.sin(m))  # thread sags toward the centre
            segs += [(p, mid), (mid, q)]
    return segs


def sketch(segs, width: float, plane: bd.Plane, centre=(0.0, 0.0), scale=(1.0, 1.0)) -> bd.Sketch:
    """Thin rectangles along each segment, on `plane`, in plane-local coordinates."""
    faces = []
    for (x0, y0), (x1, y1) in segs:
        x0, x1 = centre[0] + x0 * scale[0], centre[0] + x1 * scale[0]
        y0, y1 = centre[1] + y0 * scale[1], centre[1] + y1 * scale[1]
        L = math.hypot(x1 - x0, y1 - y0)
        if L < 1e-4:
            continue
        rect = bd.Rectangle(L + width, width)  # + width: strands overlap at joints, no gaps
        faces.append(bd.Location(((x0 + x1) / 2, (y0 + y1) / 2, 0), (0, 0, math.degrees(math.atan2(y1 - y0, x1 - x0)))) * rect)
    sk = faces[0]
    for f in faces[1:]:
        sk = sk + f
    return plane * sk


def wrap(body: bd.Solid, web_faces: bd.Sketch, depth: float, skin: float = 0.012, keep: bd.Solid | None = None) -> bd.Shape | None:
    """Extrude the web through the body both ways, then keep only the part inside a thin skin just outside
    the paint. `keep` (optional box) limits which surfaces of the car this web may land on."""
    prism = bd.extrude(web_faces, depth, both=True)
    # shortcut: OCC's offset_3d fails on these filleted hulls, so the skin is a scaled copy (about the bbox
    # centre, per axis) - thickness is exact at the extremes, a little thinner in hollows. Fine for paint.
    bb = body.bounding_box()
    c = bb.center()
    by = tuple(1 + skin / max(s / 2, 1e-3) for s in (bb.size.X, bb.size.Y, bb.size.Z))
    outer = bd.Pos(c) * bd.scale(bd.Pos(-c) * body, by=by)
    shell = outer - body
    out = prism & shell
    if keep is not None:
        out = out & keep
    return out if out.volume > 1e-7 else None
