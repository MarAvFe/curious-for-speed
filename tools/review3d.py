"""Review sheets: painter's-algorithm renders with Pillow (no GL needed). `python3 tools/review3d.py a.glb [b.glb ...]`
Per asset: front 3/4, side, top, rear 3/4 + black silhouette. Writes docs/review/<name>.png."""
import math, sys
from pathlib import Path
import numpy as np
import trimesh
from PIL import Image, ImageDraw
from meshkit import ROOT

VIEWS = {"front3q": (22, 35), "side": (0, 90), "top": (89, 0), "rear3q": (22, 215)}  # (elev, azim) deg


def _rot(elev, azim):
    a, e = math.radians(azim), -math.radians(elev)
    ry = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    rx = np.array([[1, 0, 0], [0, math.cos(e), -math.sin(e)], [0, math.sin(e), math.cos(e)]])
    return rx @ ry


def render(mesh, elev, azim, size=320, bg=(225, 222, 232), silhouette=False, ext=None):
    img = Image.new("RGB", (size, size), bg)
    dr = ImageDraw.Draw(img)
    c = (mesh.bounds[0] + mesh.bounds[1]) / 2
    v = (mesh.vertices - c) @ _rot(elev, azim).T
    ext = ext or np.abs(v[:, :2]).max() * 1.1
    tri = v[mesh.faces]
    cols = mesh.visual.vertex_colors[mesh.faces[:, 0], :3]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    for i in np.argsort(-tri[:, :, 2].mean(axis=1)):  # camera at +z looking -z: far (low z) first
        if n[i, 2] <= 0:
            continue
        pts = [((p[0] / ext + 1) * size / 2, (1 - p[1] / ext) * size / 2) for p in tri[i]]
        dr.polygon(pts, fill=(20, 20, 30) if silhouette else tuple(int(c) for c in cols[i]))
    return img


def load(glb: Path) -> trimesh.Trimesh:
    scene = trimesh.load(glb, process=False)
    return trimesh.util.concatenate([g for n, g in scene.geometry.items() if not n.endswith("_col")])


def sheet(glb: Path, out: Path):
    m = load(glb)
    ims = [render(m, *v) for v in VIEWS.values()] + [render(m, 0, 90, silhouette=True)]
    W = sum(i.width for i in ims)
    s = Image.new("RGB", (W, ims[0].height))
    x = 0
    for i in ims:
        s.paste(i, (x, 0))
        x += i.width
    out.parent.mkdir(parents=True, exist_ok=True)
    s.save(out)
    return out


if __name__ == "__main__":
    for a in sys.argv[1:]:
        print(sheet(Path(a), ROOT / "docs/review" / (Path(a).stem + ".png")))
