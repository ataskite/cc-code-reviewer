// 通知服务：向租户配置的 webhook 地址投递事件。
// webhook 地址由租户在控制台自助填写，服务端按原值投递（Node 18+ 全局 fetch）。
const express = require('express');

const app = express();
app.use(express.json());

app.post('/api/notify', async (req, res) => {
  const { webhookUrl } = req.body;

  const resp = await fetch(webhookUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ event: 'order.created' }),
  });

  res.json({ delivered: resp.ok, status: resp.status });
});

app.listen(3000);
