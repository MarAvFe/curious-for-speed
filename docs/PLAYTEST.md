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

## Playtest log

### 2026-11-03: v0.2.0 (split screen, Nihilore music)
What we saw:
- Very excited to win and to go fast.
- Forgets the horn at first, slowly picks it up.
- Excited to beat the others, with no shame at all in losing (yet). Yells at the screen and taunts the other cars.
- Scrolls endlessly through the car menu.
- Doesn't care about track selection, just confirms and moves on.
- Absolutely loved playing together. Even when dad won he didn't care, he was just enjoying it.
- Bug: in multiplayer, player 1's nitro stayed empty. Most likely the nitro key was held down the whole time, which kept the tank at zero. Fixed: after running dry, nitro waits until the tank is back to 30 %, so holding it still gives bursts and a filling gauge.

What it suggests (Claude's reading, not his words):
- Two players is the main mode now: worth tuning for, not a side feature.
- The car menu is a toy in itself: things like reveals, sounds and spinning cars pay off there. The track menu could pick for him, or simply stay one press.
- Taunting rivals fits "rivals with personality" in `docs/NEXT.md`: give him rivals worth yelling at.
- Horn reactions (`docs/NEXT.md` #1) should help him remember the horn.
