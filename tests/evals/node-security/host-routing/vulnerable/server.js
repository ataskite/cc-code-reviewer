const express = require('express');
const http = require('node:http');
const app = express();
app.use(express.json());
app.post('/preview', (req, res) => {
  const rb = req.body;
  const call = http.request('http://ingress.example.test/public/preview', {
    method: 'POST', headers: rb.header
  }, upstream => upstream.pipe(res));
  call.on('error', () => res.sendStatus(502));
  call.end(JSON.stringify({ query: rb.query }));
});
app.listen(3000);
