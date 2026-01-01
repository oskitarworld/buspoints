Generate icon variants for Flutter assets

This small helper creates multi-density variants of PNG icons so Flutter can
load the appropriate resolution depending on device pixel ratio.

What it does
- Reads PNG files from a source directory (default `assets/icons`).
- Writes resized variants into the same out directory under `1.0x/`, `1.5x/`, `2.0x/`, `3.0x/` subfolders.
- Default base size is 48px for the 1.0x variant; you can change it.

Requirements
- Node.js (>=14)
- npm

Install dependencies

```bash
npm install jimp
```

Run the generator

```bash
node tool/generate_icon_variants.js --src=assets/icons --out=assets/icons --base=48
```

Options
- --src: source directory to read PNGs from (default: assets/icons)
- --out: output directory where variant folders will be created (default: assets/icons)
- --base: base size in pixels for the 1.0x variant (default: 48)

Notes
- The script ignores files already inside x-density subfolders.
- After running, Flutter will pick up the asset variants automatically if you include the base path in `pubspec.yaml` (e.g. `assets/icons/`).
- You may want to optimize the source PNGs (trim transparent padding, export at square sizes) for best results.
