"""README images -> docs/media/. Gameplay from docs/shots (run the --shots/--snap/--podium tours first),
models rendered straight from the generated assets. `python3 tools/media.py`"""
from pathlib import Path
from PIL import Image, ImageDraw
import review3d
import props
from palette import TRACKS
from meshkit import ROOT
from cars import PLAYABLE

OUT = ROOT / "docs/media"
SHOTS = ROOT / "docs/shots"
BG = (34, 28, 58, 255)


def grid(ims, cols, pad=6, bg=BG):
    w, h = ims[0].size
    rows = (len(ims) + cols - 1) // cols
    s = Image.new("RGBA", (cols * w + (cols + 1) * pad, rows * h + (rows + 1) * pad), bg)
    for i, im in enumerate(ims):
        s.alpha_composite(im.convert("RGBA"), (pad + (i % cols) * (w + pad), pad + (i // cols) * (h + pad)))
    return s


def shot(name, size=(640, 360)):
    return Image.open(SHOTS / name).convert("RGBA").resize(size, Image.LANCZOS)


def model(m, elev=18, azim=40, size=260):
    return review3d.render(m, elev, azim, size=size, bg=None)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # gameplay: one hero shot per track
    grid([shot(f"track_{n}_{k:02d}.png") for n, k in ((1, 3), (2, 2), (3, 1), (4, 3))], 2).save(OUT / "tracks.png")
    grid([shot("title.png"), shot("reveal.png"), shot("podium_1.png")], 3).save(OUT / "flow.png")
    # the 8 playable shapes, front and back (the chase camera shows the back all race)
    cars = []
    for i in range(8):
        m = review3d.load(ROOT / f"assets/cars/car_{PLAYABLE[i]}.glb")
        cars += [model(m, 18, 40), model(m, 22, 215)]
    grid(cars, 8, bg=(225, 222, 232, 255)).save(OUT / "cars.png")
    # traffic + a prop from every track
    traffic = [model(review3d.load(ROOT / f"assets/cars/traffic_{t}_{k}.glb"), 18, 40, 200) for t, k in (("hatch", 0), ("van", 1), ("pickup", 3))]
    p1, p2, p3, p4 = TRACKS[1], TRACKS[2], TRACKS[3], dict(TRACKS[4])
    from palette import LIVERIES
    pieces = [props.building(p1, 16, 16, 40, 2, outline=0.12), props.crane(p1), props.palm(p1, 1), props.billboard(p1, LIVERIES[1][1], LIVERIES[1][2], 40),
              props.mesa(p2, 1), props.cactus(p2, 2), props.neon_sign(p3, 1), props.pine(p4, 1), props.peak(p4, 2), props.gantry(p1, 21.0)]
    grid(traffic + [model(m, 15, 35, 200) for m in pieces], 7, bg=(225, 222, 232, 255)).save(OUT / "props.png")
    # icons
    names = ["play", "restart", "home", "gear", "flame", "flag", "web", "light", "speed_3", "track_1", "track_2", "track_3", "track_4"]
    icons = [Image.open(ROOT / f"assets/ui/icon_{n}.png").convert("RGBA") for n in names]
    grid(icons, len(icons), bg=(120, 110, 150, 255)).save(OUT / "icons.png")
    print(sorted(p.name for p in OUT.glob("*.png")))


if __name__ == "__main__":
    main()
