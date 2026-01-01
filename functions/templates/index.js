const fs = require('fs');
const path = require('path');
const mustache = require('mustache');

// Directory where templates live (this file is inside functions/templates)
const TEMPLATES_DIR = __dirname;

function loadTemplate(name) {
  const htmlPath = path.join(TEMPLATES_DIR, `${name}.html`);
  const txtPath = path.join(TEMPLATES_DIR, `${name}.txt`);
  const html = fs.existsSync(htmlPath) ? fs.readFileSync(htmlPath, 'utf8') : null;
  const text = fs.existsSync(txtPath) ? fs.readFileSync(txtPath, 'utf8') : null;
  return { html, text };
}

// Preload templates that exist in the folder. Adjust list if you add more templates.
const available = [
  'welcome',
  'pending_reminder',
  'subscription_confirmed',
  // 30-day subscription expiry reminder
  'subscription_expiry_30'
];

const templates = {};
for (const name of available) {
  templates[name] = loadTemplate(name);
}

function render(name, view) {
  const tpl = templates[name] || loadTemplate(name);
  const html = tpl.html ? mustache.render(tpl.html, view) : null;
  const text = tpl.text ? mustache.render(tpl.text, view) : null;
  return { html, text };
}

module.exports = { render, loadTemplate, templates };
