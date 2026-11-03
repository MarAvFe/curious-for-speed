"""Music: tracks by Nihilore (nihilore.com, CC BY 4.0). Downloads each MP3 once into build/music_src/,
then transcodes to Ogg Vorbis at a fixed loudness so every track sits at the same level under the engine and effects.
Change made (as CC BY asks us to state): gain + transcode only; titles are kept exactly (Nihilore's rule).
Needs network on first run and ffmpeg on PATH. Run: python3 tools/music.py"""
import re, subprocess, urllib.request
from meshkit import ROOT

SRC = "https://www.nihilore.com/s/{}.mp3"
CACHE = ROOT / "build/music_src"
OUT = ROOT / "assets/audio"
TARGET_LUFS = -21.0  # engine loop is ~-22 LUFS, fanfare ~-25: music sits with the car, not over it

# slot -> (exact title for the credits, file slug on nihilore.com)
TRACKS = {
    "music_title": ("Disconnected", "Disconnected"),            # garage/menus: steady synthwave, starts in 2 s
    "music_harbor": ("Motion Blur", "Motion-Blur"),             # dusk city: full energy from bar one
    "music_canyon": ("This Is My Time", "This-Is-My-Time"),     # desert highway: driving metal, starts in 2 s
    "music_downtown": ("Chalk Ninja", "Chalk-Ninja"),           # neon night: most percussive
    "music_frost": ("An Unwavering Will", "An-Unwavering-Will"),  # mountain climbs
    "music_podium": ("A Tremendous Thing", "A-Tremendous-Thing"),  # flat podium
}


def lufs(path) -> float:
    err = subprocess.run(["ffmpeg", "-nostats", "-i", str(path), "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", err)[-1])


def build() -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / ".gdignore").touch()  # keep Godot from importing (and exporting) the source MP3s
    rep = {}
    for slot, (title, slug) in TRACKS.items():
        mp3 = CACHE / f"{slug}.mp3"
        ogg = OUT / f"{slot}.ogg"
        if not mp3.exists() and ogg.exists():  # fresh clone: the committed ogg is already the built file
            continue
        if not mp3.exists():
            req = urllib.request.Request(SRC.format(slug), headers={"User-Agent": "curious-for-speed-build"})
            mp3.write_bytes(urllib.request.urlopen(req, timeout=60).read())
        gain = TARGET_LUFS - lufs(mp3)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(mp3), "-af", f"volume={gain:.2f}dB",
                        "-c:a", "libvorbis", "-q:a", "4", "-map_metadata", "-1", str(ogg)], check=True)
        got = lufs(ogg)
        assert abs(got - TARGET_LUFS) < 1.0, f"{slot} loudness {got}"
        rep[slot] = {"title": title, "lufs": round(got, 1), "mb": round(ogg.stat().st_size / 1e6, 1)}
    return rep


if __name__ == "__main__":
    for k, v in build().items():
        print(k, v)
