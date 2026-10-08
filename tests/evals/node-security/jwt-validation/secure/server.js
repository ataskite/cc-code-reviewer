const express = require('express');
const jwt = require('jsonwebtoken');
if (!process.env.JWT_PUBLIC_KEY) throw new Error('key missing');
const app = express();
app.get('/admin/export', (req, res) => {
  const bearer = req.get('Authorization') || '';
  if (!bearer.startsWith('Bearer ')) return res.sendStatus(401);
  let claims;
  try {
    claims = jwt.verify(bearer.slice(7), process.env.JWT_PUBLIC_KEY, {
      algorithms: ['RS256'], issuer: 'https://issuer.example.test', audience: 'export-api'
    });
    if (typeof claims.exp !== 'number' || !Number.isFinite(claims.exp) ||
        claims.exp <= Date.now() / 1000 || typeof claims.sub !== 'string') return res.sendStatus(401);
  } catch (err) {
    return res.sendStatus(401);
  }
  if (claims.role !== 'admin') return res.sendStatus(403);
  res.json({ exportAccepted: true, actor: claims.sub });
});
app.listen(3000);
