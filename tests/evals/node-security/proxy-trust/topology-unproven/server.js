const express = require('express');
const app = express();
app.set('trust proxy', 1);
app.get('/admin/export', (req, res) => {
  if (req.ip !== '192.0.2.10') return res.sendStatus(403);
  res.json({ exportAccepted: true });
});
app.listen(3000);
