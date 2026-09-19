1. model differential
2. get speedometer needle to move
3. get the rpm accurate to reality
4. NPC needs controls---also needs 1. done for this to work correctly
	 ( and the "some steering for an imperfect setup" requirement is the real design constraint. A position-only proportional term (what's there now) can't distinguish "I'm drifting sideways" from "I'm pointed sideways" — it'll fight lateral offset by yawing the car harder, which is exactly the overshoot-into-a-turn behavior you're seeing, and it gets worse, not better, once a differential makes power delivery asymmetric under yaw. That's also why this depends on the differential work (item 3) — you can't tune lane-keeping against physics that doesn't exist yet; right now the "imperfect setup" it needs to correct for isn't really modeled.

What it actually needs once the differential's in: a heading-error term, not just position-error. Correct toward zero yaw relative to track direction first, with lateral offset as a secondary/slower correction — that's what stops a real car from oscillating down the lane. Minimum viable version is a PD controller (add a damping term against yaw rate) instead of the current bare P-on-position.

Given it's also going to own staging and burnout behavior later, pulling this out of InputModule into its own NPCController (or a module the same shape as your other modules — NPCDriverModule) is the right call now rather than growing InputModule's AI branch further. VehicleController already treats input as a black box via is_player_controlled branching, so this is a clean seam — swap what's plugged in, not a rewrite of VehicleController.)

5. get controls unlocked when tree starts for red light fouls possibilities
	 ( — confirmed, here's the actual gap:**

The lock isn't in `get_steering()` — that one's already ungated for the player. It's `get_throttle()`:

```gdscript
func get_throttle() -> float:
	if not race_started:
		return 0.0
```

`race_started` only flips true in `InputModule.start_race()`, which only gets called from `VehicleController.start_race()`, which is only ever called from `race_manager._on_green_light()`. Nothing in `race_manager.gd` connects to the `tree_started` signal at all — it only wires up `green_light`. `timing_system.gd` connects to `tree_started` for its own foul-detection bookkeeping, but that's a separate listener; it doesn't touch the vehicle. So the car is physically incapable of moving until green, which is why you can't draw a foul — the timing system's red-light logic is sitting there ready and working, it just never gets triggered because the throttle can't produce the crossing.

Fix needs two states, not one, because `race_started` is also what starts the AI's reaction-timer clock (`ai_reaction_timer` only accumulates once `get_ai_throttle()` passes the `race_started` check) — if you just relax that single flag to unlock at tree-start, you also unlock the AI's reaction timer at tree-start, and its "reaction time" stops meaning anything relative to green.

So: split it.
- Add `controls_armed: bool` to `InputModule`, set true on `tree_started` (not `race_started`).
- `get_throttle()`'s player branch checks `controls_armed` instead of `race_started`.
- `get_ai_throttle()` keeps checking `race_started` exactly as-is — AI still can't jump.
- `race_manager.gd` needs a new connection: `start_tree_node.tree_started.connect(_on_tree_armed)`, and that handler calls into each vehicle to arm it (e.g. `player_vehicle.arm_controls()` → `input.controls_armed = true`).

Brake and clutch are already ungated for the player, don't need touching.)
