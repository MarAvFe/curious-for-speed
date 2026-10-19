"""Bold, wordless UI icons (Pillow polygons, 4x supersampled). White fill + soft dark rim; tinted in-engine."""
import math
from PIL import Image, ImageDraw
from meshkit import ROOT

S = 512  # draw size; saved at 128


def circ(cx, cy, r, n=40, a0=0, a1=2 * math.pi):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / (n - 1)), cy + r * math.sin(a0 + (a1 - a0) * i / (n - 1))) for i in range(n)]


def star(cx, cy, r1, r2, n=5):
    return [(cx + (r1 if i % 2 == 0 else r2) * math.sin(math.pi * i / n), cy - (r1 if i % 2 == 0 else r2) * math.cos(math.pi * i / n)) for i in range(2 * n)]


def _chevrons(d, n):
    """n forward chevrons = speed; dim outlines for the missing ones so the scale is visible."""
    for i in range(3):
        x = 70 + i * 120
        pts = [(x, 120), (x + 80, 120), (x + 190, 256), (x + 80, 392), (x, 392), (x + 110, 256)]
        d.polygon(pts, fill="white" if i < n else (255, 255, 255, 70))


def _web(d):
    import web as w
    for (x0, y0), (x1, y1) in w.strands(spokes=8, rings=4, r=200, sag=0.2, seed=3):
        d.line([(256 + x0, 256 + y0), (256 + x1, 256 + y1)], fill="white", width=26)


def _track(n):
    """Track icon: the real loop outline from tracks/track_N.json, as a thick ring."""
    import json
    def draw(d):
        f = ROOT / f"tracks/track_{n}.json"
        if not f.exists():
            return
        pts = [(p[0], p[2]) for p in json.loads(f.read_text())["samples"][::4]]
        xs, zs = [p[0] for p in pts], [p[1] for p in pts]
        c = ((max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2)
        k = 380 / max(max(xs) - min(xs), max(zs) - min(zs))
        q = [(256 + (x - c[0]) * k, 256 + (z - c[1]) * k) for x, z in pts]
        d.line(q + q[:1], fill="white", width=40, joint="curve")
        x0, y0 = q[0]
        d.rectangle((x0 - 34, y0 - 12, x0 + 34, y0 + 12), fill=(0, 0, 0, 0))  # start line notch
    return draw


def _flag(d):
    d.rectangle((96, 70, 120, 450), fill="white")
    for i in range(5):
        for j in range(3):
            if (i + j) % 2 == 0:
                d.rectangle((120 + i * 62, 80 + j * 62, 182 + i * 62, 142 + j * 62), fill="white")
    d.rectangle((120, 80, 430, 266), outline="white", width=14)


SHAPES = {
    "play": lambda d: d.polygon([(170, 110), (410, 256), (170, 402)], fill="white"),
    "pause": lambda d: [d.rounded_rectangle(b, 30, fill="white") for b in ((140, 110, 230, 402), (282, 110, 372, 402))],
    "restart": lambda d: [d.arc((110, 110, 402, 402), 40, 330, fill="white", width=70),
                          d.polygon([(360, 70), (420, 210), (280, 190)], fill="white")],
    "home": lambda d: [d.polygon([(256, 80), (440, 250), (72, 250)], fill="white"), d.rectangle((130, 240, 382, 420), fill="white")],
    "gear": lambda d: [d.polygon(star(256, 256, 200, 150, 8), fill="white"), d.ellipse((186, 186, 326, 326), fill=(0, 0, 0, 0))],
    "prev": lambda d: d.polygon([(340, 90), (340, 422), (120, 256)], fill="white"),
    "next": lambda d: d.polygon([(172, 90), (172, 422), (392, 256)], fill="white"),
    "car": lambda d: [d.polygon([(40, 330), (60, 250), (170, 230), (230, 160), (360, 160), (420, 240), (472, 260), (472, 330)], fill="white"),
                      d.ellipse((90, 290, 190, 390), fill="white"), d.ellipse((330, 290, 430, 390), fill="white")],
    "flame": lambda d: [d.polygon([(256, 50), (340, 180), (380, 300), (340, 410), (256, 450), (172, 410), (132, 300), (172, 180)], fill="white"),
                        d.polygon([(256, 230), (300, 320), (256, 410), (212, 320)], fill=(0, 0, 0, 0))],
    "flag": _flag,
    "web": _web,
    "dot": lambda d: d.ellipse((96, 96, 416, 416), fill="white"),
    "light": lambda d: d.ellipse((60, 60, 452, 452), fill="white"),
    "track_1": _track(1),
    "track_2": _track(2),
    "track_3": _track(3),
    "track_4": _track(4),
    "speed_1": lambda d: _chevrons(d, 1),
    "speed_2": lambda d: _chevrons(d, 2),
    "speed_3": lambda d: _chevrons(d, 3),
}


SELECT = 8  # selectable cars: 2 bodies x first 4 liveries (rivals also use liveries 4-5)


def car_thumbs(out) -> list[str]:
    """Selection-grid thumbnails rendered from the real car models (front 3/4, transparent background).
    Locked cars are the same image tinted black in-engine."""
    import review3d
    names = []
    for i in range(SELECT):
        glb = ROOT / f"assets/cars/car_{['stinger', 'brute'][i // 4]}_{i % 4}.glb"
        if not glb.exists():
            continue
        im = review3d.render(review3d.load(glb), 18, 40, size=384, bg=None)
        im = im.crop(im.getbbox()).resize((192, 96), Image.LANCZOS) if im.getbbox() else im
        canvas = Image.new("RGBA", (200, 104), (0, 0, 0, 0))
        canvas.alpha_composite(im, ((200 - im.width) // 2, (104 - im.height) // 2))
        canvas.save(out / f"icon_car_{i}.png")
        names.append(f"icon_car_{i}")
    return names


def build() -> list[str]:
    out = ROOT / "assets/ui"
    out.mkdir(parents=True, exist_ok=True)
    for name, fn in SHAPES.items():
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        fn(ImageDraw.Draw(im))
        # soft rim: dilate alpha, darken
        a = im.getchannel("A")
        rim = Image.new("RGBA", (S, S), (59, 51, 80, 0))
        from PIL import ImageFilter
        rim.putalpha(a.filter(ImageFilter.MaxFilter(25)))
        rim.alpha_composite(im)
        rim.resize((128, 128), Image.LANCZOS).save(out / f"icon_{name}.png")
    return list(SHAPES) + car_thumbs(out)


if __name__ == "__main__":
    print(build())
