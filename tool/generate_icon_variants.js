#!/usr/bin/env node
/*
  generate_icon_variants.js

  Simple Node script that resizes PNG icons into Flutter asset variant folders
  (e.g. assets/icons/1.0x/, 1.5x/, 2.0x/, 3.0x/).

  Usage:
    npm install jimp
    node tool/generate_icon_variants.js --src=assets/icons --out=assets/icons --base=48

  The script scans the src directory (non-recursively) for .png files and
  writes resized copies into the out directory under 1.0x, 1.5x, 2.0x, 3.0x.
  By default base size is 48px (1.0x). You can change --base to a different px.
*/

const fs = require('fs');
const path = require('path');
// Require Jimp and handle ESM <-> CJS default export differences across versions
const JimpModule = require('jimp');
const Jimp = (JimpModule && JimpModule.default) ? JimpModule.default : JimpModule;

if (typeof Jimp.read !== 'function') {
  console.error('Jimp.read is not available. Please ensure `jimp` is installed (try `npm install jimp`).');
  process.exit(1);
}

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { src: 'assets/icons', out: 'assets/icons', base: 48 };
  for (const a of args) {
    if (a.startsWith('--src=')) opts.src = a.split('=')[1];
    if (a.startsWith('--out=')) opts.out = a.split('=')[1];
    if (a.startsWith('--base=')) opts.base = Number(a.split('=')[1]);
  }
  return opts;
}

async function main() {
  const opts = parseArgs();
  const densities = [1.0, 1.5, 2.0, 3.0];
  if (!fs.existsSync(opts.src)) {
    console.error('Source folder not found:', opts.src);
    process.exit(1);
  }
  if (!fs.existsSync(opts.out)) fs.mkdirSync(opts.out, { recursive: true });

  const files = fs.readdirSync(opts.src).filter(f => f.toLowerCase().endsWith('.png'));
  if (files.length === 0) {
    console.warn('No PNG files found in', opts.src);
    return;
  }

  console.log(`Found ${files.length} PNG(s) in ${opts.src}. Generating variants (base=${opts.base}px)...`);

  for (const f of files) {
    const srcPath = path.join(opts.src, f);
    // skip files that are inside density folders already
    if (srcPath.includes(path.sep + '1.0x' + path.sep) || srcPath.includes(path.sep + '2.0x' + path.sep) || srcPath.includes(path.sep + '1.5x' + path.sep) || srcPath.includes(path.sep + '3.0x' + path.sep)) {
      continue;
    }
    try {
      // Read file as Buffer first to avoid platform/encoding issues where
      // Jimp.read(path) may fail to detect MIME on some setups. This also
      // allows us to validate file size.
      const fileBuf = fs.readFileSync(srcPath);
      if (!fileBuf || fileBuf.length === 0) {
        console.warn('Skipping empty file:', srcPath);
        continue;
      }
      const image = await Jimp.read(fileBuf);
      for (const d of densities) {
        const size = Math.round(opts.base * d);
        const dirName = `${d}x`;
        const outDir = path.join(opts.out, dirName);
        if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
        const outPath = path.join(outDir, f);
        const copy = image.clone();
        copy.contain(size, size, Jimp.HORIZONTAL_ALIGN_CENTER | Jimp.VERTICAL_ALIGN_MIDDLE);
        await copy.writeAsync(outPath);
        console.log(`Wrote ${outPath} (${size}x${size})`);
      }
    } catch (e) {
      console.error('Failed processing', srcPath, e);
    }
  }

  console.log('Done. Remember to run `flutter pub get` if you changed pubspec assets.');
}

main().catch(e => { console.error(e); process.exit(1); });
