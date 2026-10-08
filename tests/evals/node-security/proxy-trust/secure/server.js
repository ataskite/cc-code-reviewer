const express = require('express');
const app = express();
app.set('trust proxy', false);
app.get('/admin/export', (req, res) => {
  if (req.socket.remoteAddress !== '127.0.0.1' && req.socket.remoteAddress !== '::1') {
    return res.sendStatus(403);
  }
  res.json({ exportAccepted: true });
});
app.listen(3000, '127.0.0.1');
