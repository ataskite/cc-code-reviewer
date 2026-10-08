const express = require('express');
const jwt = require('jsonwebtoken');
const app = express();
app.get('/admin/export', (req, res) => {
  const token = (req.get('Authorization') || '').replace(/^Bearer /, '');
  const claims = jwt.decode(token);
  if (!claims || claims.role !== 'admin') return res.sendStatus(403);
  res.json({ exportAccepted: true, actor: claims.sub });
});
app.listen(3000);
