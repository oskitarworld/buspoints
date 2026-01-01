/*
Export Pdis_full documents and generate a self-contained HTML viewer using Leaflet.
Usage:
  node tool/export_and_build_viewer.js --serviceAccount=tool/sa.json --out=tool/pdis_full_viewer.html --limit=2000

The script will:
- connect to Firestore using the service account
- fetch up to `limit` documents from `Pdis_full`
- produce an HTML file with embedded JSON data and a Leaflet map showing markers
*/

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

const saPath = argv.serviceAccount || argv.s || 'tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json';
const outPath = argv.out || argv.o || 'tool/pdis_full_viewer.html';
const limit = parseInt(argv.limit || argv.l || '2000', 10);

if (!fs.existsSync(saPath)) {
  console.error('Service account not found:', saPath);
  process.exit(1);
}

const sa = require(path.resolve(saPath));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const firestore = admin.firestore();

(async () => {
  try {
    console.log('Querying up to', limit, 'documents from Pdis_full...');
    const snap = await firestore.collection('Pdis_full').limit(limit).get();
    const docs = [];
    snap.forEach(d => {
      const data = d.data();
      docs.push({
        id: d.id,
        name: data.name || '',
        description: data.description || '',
        latitude: data.latitude || data.lat || null,
        longitude: data.longitude || data.lon || data.lng || data.long || null,
        category: data.category || null,
        iconPath: data.iconPath || null
      });
    });
    console.log('Fetched', docs.length, 'documents');

    const html = buildHtml(docs);
    fs.writeFileSync(outPath, html, 'utf8');
    console.log('Wrote viewer to', outPath);
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(2);
  }
})();

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function buildHtml(docs) {
  // center map on average coordinates if available
  const coords = docs.filter(d => d.latitude && d.longitude);
  let center = [40.0, -3.0];
  let zoom = 5;
  if (coords.length > 0) {
    const avgLat = coords.reduce((s, d) => s + d.latitude, 0) / coords.length;
    const avgLng = coords.reduce((s, d) => s + d.longitude, 0) / coords.length;
    center = [avgLat, avgLng];
    zoom = 6;
  }

  const dataJson = JSON.stringify(docs);

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Pdis_full viewer</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <style>
    body, html, #map { height: 100%; margin: 0; padding: 0 }
    .info { position: absolute; top: 8px; left: 8px; z-index: 400; background: rgba(255,255,255,0.9); padding:8px; border-radius:6px }
  </style>
</head>
<body>
  <div class="info">Documentos: ${docs.length} — abrir en navegador local</div>
  <div id="map"></div>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script>
    const docs = ${dataJson};
    const map = L.map('map').setView(${JSON.stringify(center)}, ${zoom});
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '© OpenStreetMap contributors'
    }).addTo(map);

    const defaultIcon = L.icon({
      iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
      iconSize: [25,41], iconAnchor: [12,41], popupAnchor: [1,-34]
    });

    let bounds = [];
    for (const d of docs) {
      if (!d.latitude || !d.longitude) continue;
      let icon = defaultIcon;
      if (d.iconPath) {
        // use remote iconPath; size fallback
        icon = L.icon({ iconUrl: d.iconPath, iconSize: [36,36], iconAnchor: [18,36], popupAnchor: [0,-28] });
      }
      const m = L.marker([d.latitude, d.longitude], { icon }).addTo(map);
  const html = '<b>' + escapeHtml(d.name || '') + '</b><br>' + escapeHtml(d.description || '') + '<br><small>' + escapeHtml(String(d.id)) + '</small>';
      m.bindPopup(html);
      bounds.push([d.latitude, d.longitude]);
    }
    if (bounds.length) map.fitBounds(bounds, { maxZoom: 14 });

    function escapeHtml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') }
  </script>
</body>
</html>`;
}
