"""One palette for everything. Deeper and more saturated than rail-shooter (dusk racing, not pastel nursery),
still hue-shifted ramps (see meshkit.ramp). Writes assets/palette.json."""
from meshkit import ramp, write_json, ROOT

BASE = {
    "tyre": ramp(250, 0.10, 0.10, 0.32),
    "rim": ramp(220, 0.08, 0.50, 0.90),
    "glass": ramp(215, 0.35, 0.18, 0.62, 4),
    "head": ["#fff6c8"] * 3,
    "tail": ["#ff3d5a"] * 3,
    "blink": ["#ffb43d"] * 3,
    "chrome": ramp(230, 0.06, 0.45, 0.92),
}

# Liveries: (name, paint ramp, web ramp). Webs always contrast the paint. The first 4 are pickable, in grid order.
LIVERIES = [
    ("ember", ["#a8300f", "#e8590c", "#ff8a1f", "#ffb054", "#ffd9a0"], ramp(250, 0.10, 0.06, 0.24)),  # orange, black webs; hand-set: ramp()'s cool shift turns orange shadows red
    ("midnight", ramp(250, 0.15, 0.08, 0.30), ramp(230, 0.10, 0.75, 0.97)),   # black, white webs
    ("crimson", ramp(355, 0.75, 0.30, 0.74), ramp(250, 0.10, 0.06, 0.24)),    # red, black webs
    ("toxic", ramp(95, 0.65, 0.30, 0.78), ramp(250, 0.10, 0.06, 0.24)),       # acid green, black webs
    ("cobalt", ramp(222, 0.70, 0.26, 0.70), ramp(230, 0.10, 0.75, 0.97)),     # blue, white webs (rivals only)
    ("violet", ramp(278, 0.55, 0.24, 0.70), ramp(160, 0.55, 0.60, 0.92)),     # purple, mint webs (rivals only)
]

# Plain civilian traffic paints (no webs: racers stand out)
TRAFFIC = [ramp(45, 0.55, 0.45, 0.88), ramp(190, 0.30, 0.42, 0.88), ramp(0, 0.05, 0.55, 0.95), ramp(130, 0.30, 0.40, 0.85)]

TRACKS = {
    1: {  # Night Harbor: dusk city
        "road": ramp(250, 0.12, 0.16, 0.42), "line": ["#e9e6f2"] * 3, "curb": [ramp(355, 0.7, 0.4, 0.8), ramp(0, 0, 0.8, 0.98)],
        "wall": ramp(240, 0.12, 0.30, 0.70), "ground": ramp(255, 0.20, 0.14, 0.40), "water": ramp(230, 0.45, 0.16, 0.45),
        "bld": [ramp(250, 0.20, 0.16, 0.50), ramp(265, 0.18, 0.20, 0.55), ramp(220, 0.18, 0.18, 0.52), ramp(300, 0.15, 0.18, 0.50)],
        "win": ["#ffd37a", "#ffe6a8", "#8ff0ff"], "lamp": ["#ffd9a0"] * 3, "neon": ["#ff4fb5", "#4ff3ff", "#b6ff4f"],
        "metal": ramp(235, 0.10, 0.30, 0.75), "leaf": ramp(150, 0.35, 0.16, 0.50), "trunk": ramp(25, 0.30, 0.22, 0.55),
        "sky": ["#2b2357", "#ff9a6b"], "fog": "#5a4a7a", "light": "#ffd9b8",
    },
    2: {  # Red Canyon: desert sunset highway
        "road": ramp(20, 0.10, 0.20, 0.48), "line": ["#fff1d6"] * 3, "curb": [ramp(10, 0.7, 0.4, 0.8), ramp(40, 0.2, 0.8, 0.98)],
        "wall": ramp(30, 0.20, 0.40, 0.80), "ground": ramp(22, 0.50, 0.36, 0.72),
        "rock": ramp(12, 0.55, 0.28, 0.72), "rock2": ramp(30, 0.55, 0.34, 0.80), "cactus": ramp(120, 0.35, 0.22, 0.55),
        "win": ["#ffd37a"], "lamp": ["#ffe0a8"] * 3, "neon": ["#ff7a3d", "#ffd23d", "#4ff3ff"],
        "metal": ramp(30, 0.10, 0.35, 0.80), "leaf": ramp(110, 0.35, 0.22, 0.55), "trunk": ramp(25, 0.30, 0.25, 0.60),
        "sky": ["#ff7e5f", "#ffd59a"], "fog": "#f0a882", "light": "#fff0d8",
    },
    3: {  # Neon Downtown: night city, figure-8 with an overpass
        "road": ramp(245, 0.15, 0.12, 0.36), "line": ["#dff6ff"] * 3, "curb": [ramp(320, 0.8, 0.4, 0.8), ramp(0, 0, 0.8, 0.98)],
        "wall": ramp(250, 0.15, 0.22, 0.60), "ground": ramp(255, 0.25, 0.10, 0.30),
        "bld": [ramp(250, 0.25, 0.10, 0.38), ramp(270, 0.25, 0.12, 0.40), ramp(225, 0.25, 0.10, 0.38), ramp(300, 0.22, 0.12, 0.40)],
        "win": ["#ff4fb5", "#4ff3ff", "#b6ff4f", "#ffd37a", "#a98bff"], "lamp": ["#c8f4ff"] * 3, "neon": ["#ff4fb5", "#4ff3ff", "#b6ff4f", "#a98bff"],
        "metal": ramp(240, 0.12, 0.22, 0.65), "leaf": ramp(160, 0.35, 0.14, 0.45), "trunk": ramp(25, 0.30, 0.20, 0.50),
        "sky": ["#0f0c2e", "#7a2fa0"], "fog": "#2a1d4f", "light": "#c8d8ff",
    },
    4: {  # Frost Pass: snowy mountain road at dawn, bridge over a frozen lake
        "road": ramp(220, 0.10, 0.24, 0.50), "line": ["#ffffff"] * 3, "curb": [ramp(355, 0.7, 0.4, 0.8), ramp(0, 0, 0.85, 0.99)],
        "wall": ramp(215, 0.12, 0.45, 0.85), "ground": ramp(210, 0.25, 0.70, 0.97), "water": ramp(195, 0.45, 0.55, 0.90),
        "rock": ramp(230, 0.15, 0.28, 0.62), "rock2": ramp(220, 0.12, 0.40, 0.75), "snow": ramp(205, 0.20, 0.82, 0.99),
        "win": ["#ffd37a"], "lamp": ["#ffe6b8"] * 3, "neon": ["#ff7a3d", "#4ff3ff", "#ffd23d"],
        "metal": ramp(220, 0.10, 0.30, 0.75), "leaf": ramp(160, 0.35, 0.14, 0.40), "trunk": ramp(25, 0.30, 0.22, 0.50),
        "sky": ["#7fa8e0", "#ffd6c9"], "fog": "#e4e8f4", "light": "#fff2e6",
    },
}


def build() -> dict:
    data = {"base": BASE, "liveries": [{"name": n, "paint": p, "web": w} for n, p, w in LIVERIES],
            "tracks": {str(k): v for k, v in TRACKS.items()}}
    write_json(ROOT / "assets/palette.json", data)
    return data


if __name__ == "__main__":
    build()
