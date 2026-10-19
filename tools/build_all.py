"""One command: regenerate every asset, track, sound and icon; enforce budgets. `python3 tools/build_all.py [--review]`"""
import json, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import palette, cars, tracks, audiokit, icons, review3d
from meshkit import ROOT


def main() -> int:
    t0 = time.time()
    palette.build()
    fails = []
    c = cars.build() if "--no-cars" not in sys.argv else []  # cars are the slow part (web booleans, ~1.5 min)
    for r in c:
        if r["tris"] > r["budget"]:
            fails.append(f"{r['name']}: {r['tris']} tris > {r['budget']}")
    tr = tracks.build()
    for r in tr:
        if r["tris"] > tracks.TRACK_TRIS:
            fails.append(f"track {r['track']}: {r['tris']} tris")
    au = audiokit.build()
    ic = icons.build()
    if "--review" in sys.argv:
        for g in sorted((ROOT / "assets/cars").glob("*.glb")):
            review3d.sheet(g, ROOT / "docs/review" / (g.stem + ".png"))
    report = {"cars": c, "tracks": tr, "audio": au, "icons": ic, "fails": fails}
    (ROOT / "docs/build_report.json").write_text(json.dumps(report, indent=1, default=float))
    for r in c:
        print(f"  {r['name']:<20} {r['tris']:>6} / {r['budget']}")
    for r in tr:
        print(f"  {r}")
    print(f"audio files: {len(au)}  icons: {len(ic)}  time: {time.time() - t0:.1f}s")
    print("FAIL:\n  " + "\n  ".join(fails) if fails else "BUILD OK")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
