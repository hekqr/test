#!/usr/bin/env python3
"""Copy the sprites the game uses out of the two third-party asset pack zips.

The packs are licensed for non-commercial use and must NOT be redistributed,
so assets/thirdparty/ is git-ignored. Run this once on any new machine:

    python3 tools/import_assets.py <PostApocalypse_AssetPack.zip> <Zombie_Apocalypse_Tileset.zip>
"""
import sys, zipfile, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "thirdparty"

DIRS = ["down", "up", "side", "side-left"]
PA = {}  # dest name -> path inside PostApocalypse zip
for d in DIRS:
    PA[f"player_idle_{d}.png"] = f"Character/Main/Idle/Character_{d}_idle-Sheet6.png"
    PA[f"player_run_{d}.png"] = f"Character/Main/Run/Character_{d}_run-Sheet6.png"
    PA[f"player_punch_{d}.png"] = f"Character/Main/Punch/Character_{d}_punch-Sheet4.png"
    D = d.capitalize() if d != "side-left" else "Side-left"
    PA[f"zsmall_idle_{d}.png"] = f"Enemies/Zombie_Small/Zombie_Small_{D}_Idle-Sheet6.png"
    PA[f"zsmall_walk_{d}.png"] = f"Enemies/Zombie_Small/Zombie_Small_{D}_{'walk' if d == 'down' else 'Walk'}-Sheet6.png"
    PA[f"zsmall_attack_{d}.png"] = f"Enemies/Zombie_Small/Zombie_Small_{D}_First-Attack-Sheet4.png"
    PA[f"zbig_idle_{d}.png"] = f"Enemies/Zombie_Big/Zombie_Big_{D}_Idle-Sheet6.png"
    PA[f"zbig_walk_{d}.png"] = f"Enemies/Zombie_Big/Zombie_Big_{D}_Walk-Sheet8.png"
    PA[f"zbig_attack_{d}.png"] = f"Enemies/Zombie_Big/Zombie_Big_{D}_First-Attack-Sheet8.png"
for d, D in [("side", "Side"), ("side-left", "Side-left")]:
    PA[f"player_death_{d}.png"] = f"Character/Main/Death/Character_{d}_death1-Sheet6.png"
    PA[f"zsmall_death_{d}.png"] = f"Enemies/Zombie_Small/Zombie_Small_{D}_First-Death-Sheet6.png"
    PA[f"zbig_death_{d}.png"] = f"Enemies/Zombie_Big/Zombie_Big_{D}_First-Death-Sheet7.png"
PA.update({
    "tiles_ground.png": "Tiles/Background_Dark-Green_TileSet.png",
    "tiles_building.png": "Tiles/Buildings/Buildings_dark_TileSet.png",
    "item_food.png": "Objects/Pickable/Canned-food.png",
    "item_bandage.png": "Objects/Pickable/Bandage.png",
    "item_ammo.png": "Objects/Pickable/Bullet-box_1_Green.png",
    "item_pistol.png": "Objects/Pickable/Pistol.png",
    "loot_box_1.png": "Objects/Cardboard_1.png",
    "loot_box_2.png": "Objects/Cardboard_2.png",
    "loot_trash_1.png": "Objects/Trash-can_1.png",
    "loot_trash_2.png": "Objects/Trash-can_2.png",
    "bush_1.png": "Objects/Nature/Dark-Green/Bush_1_Dark-Green.png",
    "bush_2.png": "Objects/Nature/Dark-Green/Bush_2_Dark-Green.png",
})
PA.update({
    "item_shotgun.png": "Objects/Pickable/Shotgun.png",
    "item_bat.png": "Objects/Pickable/Bat.png",
    "tiles_roof.png": "Tiles/Roof_TileSet.png",
    "ui_hp_bar.png": "UI/HP/HP-Bar.png",
    "ui_hp_fill.png": "UI/HP/HP.png",
    "ui_hunger_bar.png": "UI/Hunger/Hunger-Bar.png",
    "ui_hunger_fill.png": "UI/Hunger/Hunger.png",
    "ui_inventory.png": "UI/Inventory/Inventory_2.png",
    "ui_cell.png": "UI/Inventory/Inventory-Cell.png",
    "ui_cell_chosen.png": "UI/Inventory/Inventory-Chosen.png",
    "ui_hotbar.png": "UI/Inventory/Quick-Access-Inventory.png",
    "ui_cursor.png": "UI/Menu/Cursor.png",
    "ui_button.png": "UI/Menu/Main Menu/Blank_Not-Pressed.png",
    "ui_button_pressed.png": "UI/Menu/Main Menu/Blank_Pressed.png",
    "ui_bullet_pistol.png": "UI/Bullet Indicators/Small/Pistol-Bullet_Small.png",
    "ui_bullet_pistol_empty.png": "UI/Bullet Indicators/Small/Pistol-Bullet_Small_Empty.png",
    "ui_bullet_shotgun.png": "UI/Bullet Indicators/Small/Shotgun-Bullet_Small.png",
    "ui_bullet_shotgun_empty.png": "UI/Bullet Indicators/Small/Shotgun-Bullet_Small_Empty.png",
    "icon_food.png": "UI/Inventory/Objects/Icon_Canned-food.png",
    "icon_bandage.png": "UI/Inventory/Objects/Icon_Bandage.png",
    "icon_ammo_pistol.png": "UI/Inventory/Objects/Icon_Bullet-box_Green.png",
    "icon_ammo_shotgun.png": "UI/Inventory/Objects/Icon_Bullet-box_Red.png",
    "icon_pistol.png": "UI/Inventory/Objects/Icon_Pistol.png",
    "icon_shotgun.png": "UI/Inventory/Objects/Icon_Shotgun.png",
    "icon_bat.png": "UI/Inventory/Objects/Icon_Bat.png",
})
for i in range(1, 6):
    PA[f"grass_{i}.png"] = f"Objects/Nature/Dark-Green/Grass_{i}_Dark-Green.png"
for i, n in enumerate(["1_Spruce", "2_Spruce-Sparse", "3_Normal", "5_Big", "6_Big-pine",
                       "7_Birch", "8_Birch", "9_Small-oak", "10_Small-oak"], 1):
    PA[f"tree_{i}.png"] = f"Objects/Nature/Dark-Green/Tree_{n}_Dark-Green.png"

ZS = "Zombie Apocalypse Tileset/Organized separated sprites/"
ZA = {"item_water.png": ZS + "Pickable Items and Weapons/Zombie-Tileset---_0341_Capa-342.png"}
for i, n in enumerate(range(384, 389), 1):
    ZA[f"blood_{i}.png"] = ZS + f"Random Blood Stains/Zombie-Tileset---_0{n}_Capa-{n + 1}.png"


def extract(zip_path, mapping):
    with zipfile.ZipFile(zip_path) as z:
        names = {n.split("/", 1)[-1] if not n.startswith("Zombie") else n: n for n in z.namelist()}
        for dest, src in mapping.items():
            real = names.get(src) or next((n for n in z.namelist() if n.endswith(src)), None)
            if real is None:
                sys.exit(f"missing in {zip_path}: {src}")
            (OUT / dest).write_bytes(z.read(real))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    OUT.mkdir(parents=True, exist_ok=True)
    extract(sys.argv[1], PA)
    extract(sys.argv[2], ZA)
    print(f"Imported {len(PA) + len(ZA)} files into {OUT}")
