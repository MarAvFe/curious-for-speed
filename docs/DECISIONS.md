# Decisions

Format: reading taken — reason — how to change.

## Setup (2026-10-18)
- **New sibling project**, `~/web-racer`. rail-shooter is untouched. Files copied from it (and then adapted): input bindings, save, audio bus, scene flow, icon menu, parent menu, audio helpers, palette ramps/bake, icon renderer, MIT licence, export presets.
- **Same engine and pins:** Godot 4.7.2, Compatibility renderer, unshaded vertex colour, retro 640×360 on by default (parent menu toggles it).
- **Geometry: build123d 0.13** (OpenCascade) for cars and props, as asked. The **road ribbon is numpy** (a 2 km sweep through OCC would be slow and tessellate badly), and so are the embankment and tunnel arch. build123d solids are tessellated to trimesh and flat-shaded by the same palette bake as rail-shooter.
- **Web skin:** `offset_3d` fails on the filleted car hulls, so the skin the webs live in is a per-axis scaled copy of the body (`tools/web.py`, marked `shortcut:`).
- **No xvfb on this machine** (installing it needs sudo). Bots and checks run `--headless`. Screenshot runs open a Godot window on WSLg for ~20 s, so they are only run with the user's OK; `run_tests.sh` uses `xvfb-run` automatically once installed.

## User answers (2026-10-18)
- **Rivals:** "flat podium, just a bar with all players present". Read as: there are rivals and a race, but **no places are ever shown**. The HUD is one bar with every racer on it, and the finish lines all four cars up side by side at the same height. Rivals rubber-band (±12 %) so they stay in sight.
- **Steering:** assisted. Throttle is automatic, left/right steers, down brakes, nitro is a hold button. The car can't spin or turn round.
- **Scope:** vertical slice, 2 tracks. No sticker book or unlocks: all 12 cars are pickable from the start.

## Gameplay readings
- **Curve push** = curvature × v² × 0.15 m/s outward (about 3 m/s on the tightest curve at cruise). It's there to make him lean into turns. The assist scales it down by up to 60 % after repeated bumps.
- **Near miss** = overtaking traffic with less than 1.6 m between the cars while going 4 m/s faster: +20 % nitro and a swish. **Drafting** behind a rival fills 12 %/s. A slow passive refill (3 %/s) means the tank is never empty for long.
- **Horn:** traffic within 80 m ahead and 3.5 m sideways moves one lane away from you, hazards flashing. The bot honks every 4 s to exercise this.
- **Gates:** the railway crossing's two arms take turns (one half of the road is always open), and the bell rings when they swap. A car can't drive into a closed arm and waits until it lifts. Traffic queues politely. Sliding barriers sweep ±5.5 m across the 18 m road and always leave a side open. Rivals and the bot predict where the barrier will be when they arrive.
- **Traffic recycling:** traffic more than 120 m behind the player reappears 260–480 m ahead in a lane with room, so traffic density follows the player.
- **Start:** the player is last on the grid (overtaking is the fun). Holding nitro through GO gives a rocket start.
- **Car sizes are analytic** (2.0 × 4.6 m boxes in track space). Traffic is heavier in collisions, so racers bounce off it.
