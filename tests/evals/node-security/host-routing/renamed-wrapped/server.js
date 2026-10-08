const express = require('express');
const { relay } = require('./transport');
const app = express();
app.use(express.json());
app.post('/preview', (req, res) => {
  const packet = { metadata: req.body.envelope, value: req.body.query };
  relay(packet, res);
});
app.listen(3000);
