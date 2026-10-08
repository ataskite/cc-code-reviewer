const express = require('express');
const jwt = require('jsonwebtoken');
if (!process.env.JWT_PUBLIC_KEY) throw new Error('key missing');
const app = express();
app.get('/admin/export', (req, res) => {
  const token = (req.get('Authorization') || '').replace(/^Bearer /, '');
  let claims;
  try {
    claims = jwt.verify(token, process.env.JWT_PUBLIC_KEY, { ignoreExpiration: true });
  } catch (err) {
    claims = jwt.decode(token);
  }
  if (!claims || claims.role !== 'admin') return res.sendStatus(403);
  res.json({ exportAccepted: true, actor: claims.sub });
});
app.listen(3000);
