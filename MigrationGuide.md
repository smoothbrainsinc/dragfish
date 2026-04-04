# Migration Guide: Old Project → New Project

## What to Copy (Assets & Scenes)

### ✅ COPY THESE - They're Good!

#### 1. **3D Assets**
```
OLD: ~/test-vehicles/assets/models/
NEW: drag_racing_game/assets/models/

Copy:
- Track meshes (.glb, .gltf)
- Start tree 3D model
- Vehicle 3D models
- Environment assets
```

#### 2. **Blender Source Files**
```
Keep separate or in:
drag_racing_game/blender_sources/
- track.blend
- vehicles.blend
- start_tree.blend
```

#### 3. **Materials & Textures**
```
OLD: ~/test-vehicles/assets/materials/
NEW: drag_racing_game/assets/materials/

Copy all:
- .material files
- Texture images
```

#### 4. **Start Tree Visual Setup**
Your start tree 3D structure is good! Copy:
- The EmptyX marker positions
- Light mesh positions
- Tree frame geometry

**BUT:** Don't copy the script, we'll recreate it better.

#### 5. **Track Layout**
Copy `pluto_raceway.tscn` but:
- Remove any vehicle spawning logic
- Keep checkpoint Area3D positions (we'll reconnect)
- Keep visual meshes
- Keep collision geometry

---

## What to RECREATE (Scripts)

### ❌ DON'T COPY - Rewrite With New System

#### 1. **VehicleController.gd**
**Old:** 150+ lines, handles everything
**New:** Use the modular VehicleController I provided

**What to preserve:**
- AI reaction time values (0.15s, 0.05 consistency)
- Wheel mesh rotation logic (already in new script)

#### 2. **GameManager.gd**
**Old:** HP conversion, uniform stats
**New:** Config-based system I provided

**What to preserve:**
- Lane positions: `LEFT_LANE_POS`, `RIGHT_LANE_POS`
- Folder paths concept

#### 3. **RaceManager.gd**
This can mostly stay the same! Just update:

```gdscript
# OLD:
player_vehicle = GameManager.spawn_vehicle(GameManager.player_car_data, true)

# NEW:
player_vehicle = GameManager.spawn_vehicle(GameManager.player_car_config, true)
```

#### 4. **TimingSystem.gd**
Your timing system is **actually really good**! It's signal-based and decoupled.

**Keep the structure, just update:**
- Remove any direct vehicle stat references
- Use `vehicle.get_rpm()` instead of accessing properties
- Everything else can stay the same

#### 5. **StartTree.gd**
Your start tree script is solid! Signal-based, good structure.

**Minor update needed:**
```gdscript
# In _ready(), connect to race manager:
var race_manager = get_tree().get_first_node_in_group("race_manager")
if race_manager:
	green_light.connect(race_manager.start_vehicles)
```

---

## Step-by-Step Migration Process

### Phase 1: Setup New Project (Day 1)
1. Create new project
2. Install all new scripts (from artifacts)
3. Setup input map
4. Test with ONE basic vehicle

### Phase 2: Copy Assets (Day 1-2)
1. Copy 3D models
2. Copy track scene (remove scripts)
3. Position checkpoints
4. Test track loads

### Phase 3: Recreate Vehicles (Day 2)
1. Import vehicle 3D models
2. Create VehicleBody3D scenes
3. Create .tres configs for each
4. Test spawning

### Phase 4: Connect Race Systems (Day 3)
1. Copy checkpoint positions from old track
2. Recreate RaceManager (minimal changes)
3. Adapt TimingSystem (minor updates)
4. Copy StartTree structure

### Phase 5: Polish & Test (Day 4)
1. Test full race flow
2. Tune vehicle configs
3. Verify all features work

---

## Detailed: Checkpoint Migration

Your old checkpoints are Area3D nodes. They work perfectly with new system!

### Copy from old project:
```
Old Scene: pluto_raceway.tscn
├── start_line (Area3D)
├── checkpoint_60ft (Area3D)
├── checkpoint_330ft (Area3D)
├── checkpoint_660ft (Area3D)
├── checkpoint_1000ft (Area3D)
├── speed_trap_start (Area3D)
└── finish_line (Area3D)
```

### In new project:
1. Copy these nodes exactly
2. Add to groups (for TimingSystem to find):
   - start_line → group "start_checkpoint"
   - 60ft → group "60ft_checkpoint"
   - etc.

3. TimingSystem will auto-connect!

---

## Detailed: Start Tree Migration

### Old project has:
- Tree mesh geometry ✅ (keep)
- Empty marker positions ✅ (keep)
- Light meshes ✅ (keep)
- start_tree.gd script ❓ (might keep)

### Actually, your start_tree.gd is GOOD!
It's signal-based, clean, decoupled. You can copy it directly!

Just verify these signals exist:
```gdscript
signal tree_started
signal green_light
signal race_complete
```

Your timing system already connects to these. No changes needed!

---

## Vehicle Config Creation Helper

For each of your 5-6 existing vehicles, create configs:

### Quick Template:
```
1. Load old vehicle scene
2. Note the mass value
3. Create new .tres config
4. Fill in:
   - scene_path: "res://vehicles/old_car_name.tscn"
   - mass: (value from old scene)
   - Engine: rough estimate from old HP
   - Transmission: 4-speed (3.5, 2.1, 1.5, 1.0)
   - Tires: street compound
5. Test spawn
6. Tune later
```

### Converting Old HP to New System:

**Old:** `horsepower: 300`

**New torque curve:**
```gdscript
# Peak torque ≈ HP × 1.3 Nm at ~4500 RPM
torque_curve = {
    1000: 200,
    2500: 300,
    4500: 390,  # 300 HP peak here
    6500: 350,
    7000: 320
}
```

---

## What You'll Lose (Temporarily)

### Features to re-implement later:
1. Wheel modifications system
2. Pit area UI
3. Garage UI
4. Fishing game (keep separate!)

These were custom features. Keep the old project around to reference, but build them AFTER the core race system works.

---

## Timeline Estimate

**Realistic timeline for clean start:**

| Day | Task | Hours |
|-----|------|-------|
| 1 | Setup new project, install scripts | 2-3 |
| 1 | Create first test vehicle + config | 2 |
| 2 | Copy track and assets | 2 |
| 2 | Create all vehicle configs | 2-3 |
| 3 | Adapt timing system | 2 |
| 3 | Test full race loop | 2 |
| 4 | Polish, tune, fix bugs | 4 |

**Total: ~3-4 days of focused work**

This is MUCH faster than trying to refactor the old code while keeping it working.

---

## Testing Checklist

After migration, verify:

- [ ] GameManager discovers all vehicles
- [ ] Vehicles spawn in correct lanes
- [ ] Start tree lights work
- [ ] Green light triggers movement
- [ ] Checkpoints detect vehicles
- [ ] Times are recorded
- [ ] Winner is determined correctly
- [ ] Can select different cars
- [ ] AI reacts and drives
- [ ] Manual shifting works (if implemented)

---

## Emergency: Keep Old Project!

**DO NOT DELETE THE OLD PROJECT**

Reasons:
1. Reference for UI layouts
2. Working fishing game
3. Asset backup
4. If you get stuck, you have fallback

Just don't touch it while building new one. It's your museum of "how we used to do it."

---

## The Payoff

After migration, you'll have:

✅ **Clean, modular codebase**
- No 2000-line scripts
- Easy to add features
- Each system independent

✅ **Config-driven vehicles**
- Tune without opening scenes
- Easy to create variants
- Hot-reload during testing

✅ **Proper physics foundation**
- Real gear ratios
- Torque curves
- Expandable for realism

✅ **Future-proof architecture**
- Ready for: tire temps, weight transfer, wheelies, etc.
- Won't need rewrites
- Scales to 2+ years of features

---

## Questions During Migration?

If you hit issues:
1. Check console for errors
2. Verify config resources are valid
3. Make sure autoload is setup
4. Test with ONE vehicle first
5. Ask me! (Reference which step you're on)

**You've got this. Clean start is the right move.**
