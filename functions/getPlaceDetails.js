const functions = require('firebase-functions');
const axios = require('axios');

// Cloud Function para obtener detalles de un place (geometry) usando place_id
exports.getPlaceDetails = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Methods', 'GET, POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    res.status(204).send('');
    return;
  }

  const placeId = req.query.place_id || req.body.place_id;
  if (!placeId) {
    res.status(400).json({ error: 'Missing place_id parameter' });
    return;
  }

  const apiKey = 'AIzaSyBtEYqVfNtm14WstANwadcr7SRLyhc_wCk'; // <-- usa tu server API key
  const url = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${encodeURIComponent(placeId)}&fields=geometry&key=${apiKey}`;

  try {
    const response = await axios.get(url);
    const data = response.data;
    if (data && data.status === 'OK' && data.result && data.result.geometry && data.result.geometry.location) {
      const loc = data.result.geometry.location;
      // devolver sólo lat/lng para simplicidad
      res.json({ lat: loc.lat, lng: loc.lng, result: data.result });
    } else {
      res.status(500).json({ error: 'Place details error', details: data });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
