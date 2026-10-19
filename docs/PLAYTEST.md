# Playtest guide (for the grown-up)

Run `build/windows/curious-for-speed.exe` (or `godot --path .`). He picks a car with ◀ ▶, then ▶ and a track.

## Watch for (each one is a tuning knob)
| Watch | If it goes wrong | Knob |
|---|---|---|
| Does he lean into curves and keep the car off the walls? | Constantly scraping walls → curve push too strong | `DRIFT` in `scripts/game/race.gd` (0.15) |
| Does he find the horn moves traffic? | Never notices → longer hazard flash or bigger lane shift | `_on_honk` |
| Does he use nitro on purpose, or hold it forever? | Always empty → faster refill | nitro drain 0.28/s, refill 0.03/s, near-miss +0.2 |
| Crossing gate / sliding barrier: does he "resolve the problem"? | Stuck waiting, upset → longer open phase | gate `period` in `tools/tracks.py` |
| Does he pass the rivals and stay ahead? | Never passes → leaders ease off more | `band` clamp in `_drive_ai` (0.88–1.04) |
| Too fast? | Pause → »» chevrons (60 / 80 / 100 %), or the grown-up menu (50–150 %) | |
| Does the flat podium feel like a win? | Wants a "first place" moment → tell Claude | |
| Does he notice the webs on his car (the back of it, during the race)? | | |

Write what he says out loud. Last time "no prob dad, I'll resolve that problem" became the moving gates.
