#!/usr/bin/env python3
"""Rename freenuns/*.png to clean sequential names, keeping Godot's
UID tracking intact (.import sidecar + gaggle_of_nuns.tscn updated together)."""

import re
from pathlib import Path

SPRITE_DIR = Path("assets/sprites/freenuns")
SCENE_FILE = Path("assets/sprites/gaggle_of_nuns.tscn")
NEW_PREFIX = "nun"  # change if you want a different base name

def main():
    pngs = sorted(p for p in SPRITE_DIR.glob("*.png"))
    if not pngs:
        print(f"No .png files found in {SPRITE_DIR}")
        return

    rename_map = {}  # old filename -> new filename
    for i, old_path in enumerate(pngs, start=1):
        new_name = f"{NEW_PREFIX}_{i:03d}.png"
        rename_map[old_path.name] = new_name

    # Rename png + .import sidecar, patch source_file inside the .import
    for old_name, new_name in rename_map.items():
        old_png = SPRITE_DIR / old_name
        new_png = SPRITE_DIR / new_name
        old_import = SPRITE_DIR / f"{old_name}.import"
        new_import = SPRITE_DIR / f"{new_name}.import"

        old_png.rename(new_png)
        print(f"  {old_name} -> {new_name}")

        if old_import.exists():
            text = old_import.read_text(encoding="utf-8")
            old_source_path = f"res://{SPRITE_DIR.as_posix()}/{old_name}"
            new_source_path = f"res://{SPRITE_DIR.as_posix()}/{new_name}"
            text = text.replace(old_source_path, new_source_path)
            old_import.rename(new_import)
            new_import.write_text(text, encoding="utf-8")
        else:
            print(f"    WARNING: no .import found for {old_name} (never imported yet?)")

    # Update gaggle_of_nuns.tscn to reference the new filenames
    if SCENE_FILE.exists():
        scene_text = SCENE_FILE.read_text(encoding="utf-8")
        replaced = 0
        for old_name, new_name in rename_map.items():
            pattern = re.escape(old_name)
            new_text = scene_text.replace(old_name, new_name)
            if new_text != scene_text:
                replaced += 1
            scene_text = new_text
        SCENE_FILE.write_text(scene_text, encoding="utf-8")
        print(f"\nUpdated {replaced} references in {SCENE_FILE}")
    else:
        print(f"\nWARNING: {SCENE_FILE} not found, skipped scene update")

    print(f"\nDone. Renamed {len(rename_map)} files.")

if __name__ == "__main__":
    main()
