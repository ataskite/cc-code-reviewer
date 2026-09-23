// 通知服务（不安全样例）：只按字符串前缀校验 IPv4 私网段。
// IPv4-mapped IPv6 形态（::ffff:127.0.0.1 / [::ffff:7f00:1]）不匹配任何前缀，
// 可携带进 fetch 直连 loopback/内网；IPv6 link-local（fe80::/10）同样漏检。
const express = require('express');

const app = express();
app.use(express.json());

const PRIVATE_V4_PREFIX = /^(127\.|10\.|0\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)/;

app.post('/api/notify', async (req, res) => {
  try {
    const target = new URL(req.body.webhookUrl);
    if (target.protocol !== 'https:') throw new Error('scheme');
    if (PRIVATE_V4_PREFIX.test(target.hostname)) throw new Error('private');
    const resp = await fetch(target, { method: 'POST', redirect: 'manual' });
    res.json({ delivered: resp.ok, status: resp.status });
  } catch (e) {
    res.status(400).json({ error: 'webhook_target_rejected' });
  }
});

app.listen(3000);
