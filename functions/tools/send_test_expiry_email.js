#!/usr/bin/env node
const nodemailer = require('nodemailer');
const templates = require('../templates');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');

async function main() {
  const argv = yargs(hideBin(process.argv))
    .option('to', { type: 'string', demandOption: true, describe: 'Recipient email' })
    .option('name', { type: 'string', default: 'Usuario', describe: 'User name for template' })
    .option('expiry', { type: 'string', default: new Date(Date.now() + 30*24*60*60*1000).toLocaleDateString('es-ES'), describe: 'Expiry date string to render' })
    .option('host', { type: 'string', describe: 'SMTP host (env SMTP_HOST or mail.buspoints.net)' })
    .option('port', { type: 'number', describe: 'SMTP port (env SMTP_PORT or 465)' })
    .option('secure', { type: 'boolean', describe: 'Use secure connection (env SMTP_SECURE or true)' })
    .help()
    .argv;

  const smtpEmail = process.env.SMTP_EMAIL;
  const smtpPassword = process.env.SMTP_PASSWORD;
  if (!smtpEmail || !smtpPassword) {
    console.error('Please set SMTP_EMAIL and SMTP_PASSWORD environment variables (or use your preferred method).');
    process.exit(1);
  }

  const smtpHost = argv.host || process.env.SMTP_HOST || 'mail.buspoints.net';
  const smtpPort = argv.port || Number(process.env.SMTP_PORT) || 465;
  const smtpSecure = (argv.secure !== undefined) ? argv.secure : (process.env.SMTP_SECURE === undefined ? true : (String(process.env.SMTP_SECURE) === 'true'));

  const transporter = nodemailer.createTransport({ host: smtpHost, port: smtpPort, secure: smtpSecure, auth: { user: smtpEmail, pass: smtpPassword } });

  const view = { name: argv.name, expiryDate: argv.expiry };
  const rendered = templates.render('subscription_expiry_30', view);
  const subject = 'PRUEBA: Tu suscripción expira en 30 días — BusPoints (TEST)';

  try {
    const info = await transporter.sendMail({ from: smtpEmail, to: argv.to, subject, text: rendered.text || '', html: rendered.html || undefined });
    console.log('Test email sent:', info && info.messageId ? info.messageId : info);
    process.exit(0);
  } catch (err) {
    console.error('Error sending test email:', err && err.message ? err.message : err);
    process.exit(2);
  }
}

main();
