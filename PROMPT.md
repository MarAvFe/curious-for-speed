# How this project was made

An AI coding agent (Claude, in Claude Code) built this game from the prompt below, in one long session. It started from its sibling project [rail-shooter](https://github.com/MarAvFe/rail-shooter). The agent read rail-shooter's code and carried over its methods: a generated-asset pipeline, wordless UI, no fail state, and bot playtests. It reused its input, save, audio and menu systems, then designed and built the racing game. It checked its own work with headless bot races, geometry and audio asserts, and screenshots.

Section 1 is the **bootstrap prompt**, unedited, with the agent's three clarifying questions and the answers. Section 2 lists the **follow-up directions** that changed scope. Small fixes are left out.

---

## 1. Bootstrap prompt

> I want to create a twin game. just little less "kiddo based". using build123d. but this time, the game will be a need for speed racing game. not that much like mario kart. and here's my notes from my kid playing rail-shooter today for the first time!
>
> He's testing the game we built right now! Some insights. He moves his torso when moving the ship to the sides. He did notice the flying birds. He's a bit too focused on "I need to kill those enemies". He's laughing at spamming the horn. He's actually getting the hand of navigation after 3 levels. He speaks with the games verbally, and gets excited to finish a new level. Shooting is not on toggle and he's actually shooting with intention. He's having a blast! Celebrates with "attaboy!" and I said "watch it, that door moves!" and he said," no prob dad, I'll resolve that problem". He also avoids the enemies instead of shooting.
>
> Let's build this new one then. if you can add spider-web styles to the cars, that would be cool. venom is his love, no need to use copyright content though, just webs

**Clarifying questions** (asked once, before any code):

| Question | Answer |
|---|---|
| How competitive should races be? | "flat podium. just a bar with all players present" |
| How should steering work? | Assisted free steering: auto throttle, steer + brake, hold-button nitro, no spinning out |
| How big should the first version be? | Vertical slice first: new repo, 2 tracks, traffic, rivals, nitro, horn, finish celebration, an exported build |

How the agent turned the playtest notes into mechanics (body lean → curve push, avoiding enemies → traffic to dodge, horn spam → a horn that moves traffic, "that door moves" → railway crossings and sliding barriers) is in the README.

## 2. Follow-up directions

1. "maybe obvious but don't edit rail-shooter, it was perfect. this is another new project": rail-shooter is read-only; files are copied out, never changed.
2. "can you test in a headless environment to not interrupt my screen usage?": bots, compile checks and self-tests run `--headless`. Screenshots only run with permission, or on an invisible display (`xvfb-run`) when it's installed.
3. "it is soooo good! what else? I think just adding extra tracks is enough. what else was trimmed because we did 2 verticals?": the agent listed what the slice had cut compared with rail-shooter.
4. "add 2 more tracks only. keep it with no oncoming traffic. car selection is only 8 options, not 12. and they are visible in a single matrix screen but blacked and blocked at first, he then can acquire a new car every time a track is completed, even if it's the same evry time. no specific themes but keep the original city and have another city. the rest can be others'. do add the readme and prompt mds. no need to test for 60fps, it works great already.": led to Neon Downtown (figure-8 city with an overpass), Frost Pass (snow), the 8-car unlock grid, and this file.
5. "README should have screenshots of gameplay and sprites. Also rename the project to "curious-for-speed" … also, first car is orange, then black, then red and last the other one": led to the rename, README media, and liveries ordered orange, black, red, green.
