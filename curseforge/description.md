# Free Minimap — CurseForge

## Fields

- **Project name:** Free Minimap
- **Summary:** A rectangular minimap of any size, with a region map drawn from the game's own terrain tiles around you.
- **Main category:** Map & Minimap
- **Extra categories:** HUDs
- **Logo:** `images/FreeMinimap-logo-1024.png` (400 px version included)

## Gallery (title — description)

1. `images/fmm_1_banner.png` — **Free Minimap** — The minimap at any size, with the terrain all around.
2. `images/fmm_2_shapes.png` — **Any width, any height** — A strip, a big square or a tall column: no upper limit.
3. `images/fmm_3_region.png` — **Region map** — The game's terrain tiles fill the whole rectangle; the real minimap sits on top at the same scale.
4. `images/fmm_4_options.png` — **Options** — Size, scale, button size and native zoom.
5. `images/fmm_5_region_options.png` — **Region map settings** — Tiles or map art, tile scale, disc or square, calibration.

---

## Description (paste into the Markdown editor)

# Free Minimap

**The minimap at the size you want, with the terrain all around you.**

Free Minimap turns the minimap into a rectangle whose width and height you set separately, with no upper limit: a wide strip on an ultrawide screen, a big square, or a tall column next to your chat. Coordinates sit at the top, the clock at the bottom.

## Region map

The native minimap only ever shows a few hundred yards around you: making it bigger just magnifies the picture. The **region map** fills the whole rectangle with the game's own minimap terrain tiles, centred on you and north-up, with its own zoom (mouse wheel). Where no tile exists, the world-map illustration is used instead.

The **real minimap** can stay on top of it, as a disc or a square, at exactly the same scale, so quest icons, the player arrow, gathering nodes and pings stay where they belong.

| Setting | What it does |
|---|---|
| **Width / Height** | Set separately. Sliders cover the usual range; type any value in the box, there is no upper limit. |
| **Scale** | Size of the whole minimap. |
| **Buttons & text** | Size of the buttons and texts around the minimap, independent from its size. |
| **Native zoom** | 0 (widest) to 5 (closest), remembered per character. |
| **Region map** | Terrain tiles or map art, tile scale (screen pixels per yard), map art zoom. |
| **Real minimap on top** | On or off, disc or square, fine calibration if the two layers don't line up. |
| **Tile axes** | Automatic; change it only if the terrain looks misplaced. |
| **Elements around the map** | Zone, coordinates, clock, tracking, calendar, day/night, mail, difficulty, addon compartment and zoom: place each one, scale it, and show it always, on hover or never. |
| **Profiles** | Each character gets its own profile; switch, copy, export or import them. |

Place the minimap yourself (X / Y, or unlock and drag it, kept safe in combat) or leave it to the game's Edit Mode.

## Commands

- `/fmm` — options
- `/fmm region` — region map on / off
- `/fmm axes 0-8` — tile axes (0 = automatic)
- `/fmm reset` — back to defaults

## Free Hub

Free Minimap works on its own. With **Free Hub** installed, its options open inside the hub next to the other Free addons, and a single minimap button replaces theirs.

## Credits

- Based on **DejaMinimap** (by Dejablue, Bõb, Ertkal and Eurytus), with permission.
- Minimap terrain tile data from **OpenMap** (MIT licence).
