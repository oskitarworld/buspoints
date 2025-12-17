const functions = require('firebase-functions');
const axios = require('axios');

// Cloud Function para proxy de autocompletado de Google Places
exports.placesAutocomplete = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Methods', 'GET, POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    res.status(204).send('');
    return;
  }

  const input = req.query.input || req.body.input;
  if (!input) {
    res.status(400).json({ error: 'Missing input parameter' });
    return;
  }

  const apiKey = 'AIzaSyBtEYqVfNtm14WstANwadcr7SRLyhc_wCk'; // <-- Pon aquí tu API Key de Google Maps
  const url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(input)}&key=${apiKey}&language=es`;

  try {
    const response = await axios.get(url);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
