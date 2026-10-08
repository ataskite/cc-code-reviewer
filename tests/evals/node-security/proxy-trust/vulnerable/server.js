const express = require('express');
const app = express();
app.set('trust proxy', true);
app.get('/admin/export', (req, res) => {
  if (req.ip !== '127.0.0.1') return res.sendStatus(403);
  res.json({ exportAccepted: true });
});
app.listen(3000, '0.0.0.0');
