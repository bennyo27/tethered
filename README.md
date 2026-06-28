# Tethered

A co-op climbing horror "friendslop" prototype built in Godot 4.7.

> Two to four players are roped together and must ascend a procedural vertical
> labyrinth. Something rises from the bottom. If the dark catches the lowest
> player, everyone tied to them goes down too.

**PEAK** (chaotic co-op climbing) meets **White Knuckle** (vertical horror
ascent), chained together like **Chained Together**.

## Status: graybox prototype

Local 2-player graybox. No networking yet — both player capsules exist in the
same scene; Player1 has the active camera and input. Player2 is a passive body
you can shove around to feel the tether (drive it manually / add a 2nd input
device next).

## Run it

Open `project.godot` in Godot 4.7 and press Play (F5), or:

```
godot --path . 
```

Main scene: `scenes/main/prototype.tscn`

## Controls

- WASD — move
- Space — jump (also push off a wall while grabbing)
- Mouse — look
- LMB (hold) — grab a ledge/wall to climb
- E — interact (stub)
- R — restart run
- Esc — release mouse

## Core systems

| System | Script | Notes |
|---|---|---|
| Game state | `scripts/game/game_manager.gd` | autoload `GameManager`; run state, threat depth, player roster |
| Player | `scripts/player/player_controller.gd` | FP move/jump/look + grab-to-climb + tether force intake |
| Tether | `scripts/player/tether.gd` | verlet rope visual + hard distance pull constraint |
| Threat | `scripts/world/threat_riser.gd` | rising kill-plane with rubber-band catch-up |
| Labyrinth | `scripts/world/labyrinth_generator.gd` | seeded vertical chunks, floors with climb-gaps, ledges |
| Hunter | `scripts/enemy/hunter.gd` | stub AI that rides the threat; will break off to pursue |
| HUD | `scripts/game/hud.gd` | height, dark-gap, win/lose banner |

## Roadmap

See `docs/GDD.md`. Next prototype steps:

1. Second input device / split-screen so two humans can actually test the tether.
2. Make grab-climb feel good (handhold snapping, stamina).
3. Hunter `HUNTING` state: pathfind up through gaps, grab + drag a straggler.
4. Replace graybox boxes with kit-bashed industrial geometry.
5. Networking (high-level multiplayer) for true friendslop.
