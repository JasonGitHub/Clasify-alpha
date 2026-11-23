# App icon layers (card CO)

The source of `Clasify/Assets.xcassets/AppIcon.appiconset`. Canvas 1024 × 1024, on the macOS icon grid:
the tile is the 824 px square at 100,100 with a 185 px corner radius, as the icon before it.

- `tile.svg`: the silver tile, soft white at the top to light cool silver at the bottom.
- `ring.svg`: the flat click wheel, 62% of the tile width, satin black.
- `button.svg`: the flat center button, 45% of the wheel width, light silver.
- `icon-flat.svg`: the three layers with the tile's drop shadow and a soft shadow under the wheel.
  The PNG set is this file, drawn at each size.

The three layers are kept apart for a later Icon Composer file (glass on macOS 26), which needs Xcode 26.
These files are not part of the app build.
