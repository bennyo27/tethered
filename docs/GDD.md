# Tethered — Game Design Document (prototype)

## One-liner

Co-op climbing horror: friends roped together ascend a procedural labyrinth
while a rising dark hunts them from below.

## Pillars

1. **The rope is the relationship.** Every mechanic flows through the tether.
   Your mistakes pull your friends. Saving someone costs you position. Trust
   and betrayal are physical.
2. **Up is the only safe direction.** The threat rises. Stopping is death.
   Decisions are made under constant vertical pressure.
3. **Readable chaos.** Like PEAK, failure is funny and physical, not opaque.
   You always understand *why* you fell — and who took you with them.

## Influences

- **PEAK** — co-op climbing, physicality, ragdoll comedy, shared stakes.
- **White Knuckle** — first-person vertical horror ascent, momentum, dread.
- **Chained Together** — literal tether forcing coordination.

## Core loop

1. Spawn roped at the labyrinth floor.
2. Climb / jump / mantle upward through procedural chunks, finding the gap in
   each floor.
3. Manage rope tension — don't strand a teammate, don't get yanked off.
4. Outrun the rising dark.
5. Hit a checkpoint chunk (safe-ish breather).
6. Repeat into harder, taller, meaner geometry.
7. Reach the summit together, or all die together.

## The tether (signature system)

- Soft max length; rope goes taut and applies a pull force past it.
- A falling player yanks the others toward the fall (down/sideways).
- Possible advanced verbs: belay (anchor yourself to hold a falling friend),
  cut the rope (sacrifice / betrayal), rope-swing across gaps.
- Multiplayer scaling: chain of N players; only adjacent links pull, so a
  conga-line of panic propagates.

## The rising threat

- A "dark" kill-plane creeps up, slowly accelerating.
- Rubber-bands: speeds up if the team pulls far ahead so it stays scary,
  eases off if it's close so a slow player isn't instantly doomed.
- Later: not just a plane — a presence. Fog with eyes; sound design first.

## The Hunter (enemy)

- Breaks off from the dark to actively pursue.
- Targets the isolated / lowest / slowest player — punishes bad rope play.
- Climbs through the same gaps players use; can grab and drag a straggler down.
- Prototype: stub state machine (DORMANT → RISING → HUNTING).

## Procedural labyrinth

- Vertical stack of chunks. Each: perimeter walls, a floor with one climb-gap,
  scattered climbable ledges.
- Seeded for shared layouts across future networked clients.
- Future chunk types: shafts, broken catwalks, pipe mazes, dead-ends with
  shortcuts, scripted horror setpieces, checkpoint rooms.

## Tone & aesthetic

- Industrial decay; a vertical facility / oubliette that shouldn't exist.
- Darkness below is the antagonist; light is scarce and earned.
- Audio-led horror: breathing, the creak of rope, something climbing below.
- Player comms (proximity voice eventually) is the real horror multiplier.

## Prototype milestones

**M1 (this scaffold)** — graybox tower, 2 local players, tether pull, grab-climb,
rising kill-plane, win/lose + restart.

**M2** — second real input / split-screen; tuned climbing; checkpoints; Hunter
HUNTING behavior; basic audio.

**M3** — networked multiplayer (2–4); animations; proximity voice; horror
setpieces; art pass.

## Open questions

- Friendly-fire on the rope cut: griefing vs. drama? Mode toggle?
- Stamina or no stamina for climbing? (White Knuckle has momentum, PEAK has
  stamina — pick a lane.)
- Permadeath per run vs. respawn-on-checkpoint?
