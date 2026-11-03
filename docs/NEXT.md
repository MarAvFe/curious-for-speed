# Next up

Ideas agreed on 2026-11-03, after the music update, in the order to build them. Each one keeps the game's rules: no fail state, no text, the horizon never rolls, no screen shake, and it never gets harder.

## 1. The horn wakes up the world
He laughs when he spams the horn, so make it do something on every track, not only to traffic.
- **Ideas:** birds scatter (Harbor already has birds), neon signs flicker (Downtown), tumbleweeds roll across the road (Canyon), fish jump at the frozen lake (Frost).
- **Where:** `_on_honk` in `scripts/game/race.gd` (it only moves traffic today), and `_update_birds` for the birds. Animated props need a list of nodes like `birds`. Merged chunks can't move.
- **Done when:** every track has at least one thing near the road that reacts to a honk within 80 m.

## 2. Reverse tracks
Each loop driven the other way gives 4 new tracks almost for free.
- **Where:** `tools/tracks.py`. Reverse the control points (and the heights, which go with them), then rebuild. The race code is the same in either direction.
- **Check:** gates and sliding barriers are placed with `flat_spot()` by position along the track, so they should carry over. Billboards and grandstands face the road and need checking from the other side. The Downtown overpass is still a figure-8.
- **Open question:** how he picks a reversed track without text, e.g. the same thumbnail mirrored with an arrow.

## 3. Things to collect on the road
Stars or similar along the racing line that refill nitro, so he steers *towards* something as well as away from traffic.
- **Where:** handle them like near misses (they also refill nitro), using the same position along the track and sideways offset. Place them from data in `tools/tracks.py`, like `birds` and `traffic`.
- **Keep:** missing them costs nothing, and there's no counter or score.

## 4. Rivals with personality, not more skill
"Smarter" means more fun to watch. Who wins stays the same: leading rivals still ease off.
- **Ideas:** one tucks in behind him, then pulls out and passes where he can see it; one fires a visible nitro burst on straights; one honks back when he honks.
- **Where:** `_drive_ai` in `scripts/game/race.gd`. Give each rival a fixed personality per grid slot.

## 5. More hills on existing and new tracks
- **Where:** heights in `tools/tracks.py`. Tracks use 88k–131k of the 260k triangle budget (`TRACK_TRIS`), so scenery has room.
- **Add first:** a crest/dip check next to the curve-radius one (`MIN_R`), so the camera never pitches sharply.
- **Avoid:** banked turns (the horizon would roll, unless the camera stays level) and real jumps (there are no airborne physics).

## 6. Split roads, one road on paper
The road widens and an island splits it: one side through a tunnel or barn, the other side open. He chooses, and both sides are fine.
- **Why not a real fork:** each car is one distance along one track line plus a sideways offset. Laps, the progress bar, collisions and the rivals easing off all use that single distance. A true fork means two lines and a mapping between them, which touches all of those.
- **Where:** a wider road over a stretch in `tools/tracks.py` plus a central divider handled like walls (bump, never stop). Rivals and traffic pick a side.

## Smaller items
- **Music:** songs loop end-to-start with no crossfade. Only noticeable if a race runs past the end of its song (*Chalk Ninja*, 3.6 min, is the shortest).
- **Music swaps:** if *This Is My Time* doesn't work for the desert, the next options are *Nobody* and *The Watchmaker's Four* (one line in `tools/music.py`).
- **Podium music** isn't covered by a test: the bots stop at the finish line.
