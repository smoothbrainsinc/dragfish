1. model differential
2. get speedometer needle to move
3. get the rpm accurate to reality
4. NPC needs controls---also needs 1. done for this to work correctly
     ( and the "some steering for an imperfect setup" requirement is the real design constraint. A position-only proportional term (what's there now) can't distinguish "I'm drifting sideways" from "I'm pointed sideways" — it'll fight lateral offset by yawing the car harder, which is exactly the overshoot-into-a-turn behavior you're seeing, and it gets worse, not better, once a differential makes power delivery asymmetric under yaw. That's also why this depends on the differential work (item 3) — you can't tune lane-keeping against physics that doesn't exist yet; right now the "imperfect setup" it needs to correct for isn't really modeled.

What it actually needs once the differential's in: a heading-error term, not just position-error. Correct toward zero yaw relative to track direction first, with lateral offset as a secondary/slower correction — that's what stops a real car from oscillating down the lane. Minimum viable version is a PD controller (add a damping term against yaw rate) instead of the current bare P-on-position.

Given it's also going to own staging and burnout behavior later, pulling this out of InputModule into its own NPCController (or a module the same shape as your other modules — NPCDriverModule) is the right call now rather than growing InputModule's AI branch further. VehicleController already treats input as a black box via is_player_controlled branching, so this is a clean seam — swap what's plugged in, not a rewrite of VehicleController.)
