const express = require('express');
const http = require('node:http');
const app = express();
app.use(express.json());
app.post('/preview', (req, res) => {
  if (typeof req.body.query !== 'string' || req.body.query.length > 100) return res.sendStatus(400);
  const call = http.request('http://ingress.example.test/public/preview', {
    method: 'POST', headers: { Host: 'preview.example.test', 'Content-Type': 'application/json' }
  }, upstream => upstream.pipe(res));
  call.on('error', () => res.sendStatus(502));
  call.end(JSON.stringify({ query: req.body.query }));
});
app.listen(3000);
