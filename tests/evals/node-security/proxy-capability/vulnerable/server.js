const express = require('express');
const http = require('node:http');
const app = express();
app.use(express.json());
app.post('/invoke', (req, res) => {
  const rb = req.body;
  if (!['GET', 'POST'].includes(rb.method) || typeof rb.path !== 'string' || !rb.path.startsWith('/')) {
    return res.sendStatus(400);
  }
  const call = http.request({
    hostname: 'ingress.example.test', port: 80, path: rb.path,
    method: rb.method, headers: { Host: 'orders.example.test' }
  }, upstream => upstream.pipe(res));
  call.on('error', () => res.sendStatus(502));
  call.end(JSON.stringify(rb.data));
});
app.listen(3000);
