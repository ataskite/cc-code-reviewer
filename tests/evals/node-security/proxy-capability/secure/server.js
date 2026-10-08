const express = require('express');
const session = require('express-session');
const http = require('node:http');
if (!process.env.SESSION_SECRET) throw new Error('session configuration missing');
const app = express();
app.use(express.json());
app.use(session({ secret: process.env.SESSION_SECRET, resave: false, saveUninitialized: false }));
const capabilities = Object.freeze({
  'catalog-search': Object.freeze({
    permission: 'catalog:read', service: 'ingress.example.test',
    host: 'catalog.example.test', path: '/public/search', method: 'POST'
  })
});
app.post('/invoke', (req, res) => {
  const subject = req.session.subject;
  if (!subject || !Array.isArray(subject.permissions)) return res.sendStatus(401);
  if (!Object.hasOwn(capabilities, req.body.capability)) return res.sendStatus(400);
  const cap = capabilities[req.body.capability];
  if (!subject.permissions.includes(cap.permission)) return res.sendStatus(403);
  if (typeof req.body.query !== 'string' || req.body.query.length > 100) return res.sendStatus(400);
  const call = http.request({
    hostname: cap.service, port: 80, path: cap.path, method: cap.method,
    headers: { Host: cap.host, 'Content-Type': 'application/json' }
  }, upstream => upstream.pipe(res));
  call.on('error', () => res.sendStatus(502));
  call.end(JSON.stringify({ query: req.body.query }));
});
app.listen(3000);
