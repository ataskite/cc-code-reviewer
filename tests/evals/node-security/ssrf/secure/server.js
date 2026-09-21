// 通知服务：向租户配置的 webhook 地址投递事件。
// 出站目标必须通过完整校验：scheme 白名单 + DNS 解析后的 IP 段校验 +
// redirect: 'manual' 不自动跟随，每一跳 Location 重新过同一套校验。
const express = require('express');
const dns = require('dns').promises;
const net = require('net');

const app = express();
app.use(express.json());

const ALLOWED_SCHEMES = new Set(['https:']);

function isPrivateIp(ip) {
  if (net.isIPv4(ip)) {
    const o = ip.split('.').map(Number);
    return o[0] === 10 || o[0] === 127 || o[0] === 0 ||
      (o[0] === 172 && o[1] >= 16 && o[1] <= 31) ||
      (o[0] === 192 && o[1] === 168) ||
      (o[0] === 169 && o[1] === 254);
  }
  const lo = ip.toLowerCase();
  return lo === '::1' || lo.startsWith('fe80:') || lo.startsWith('fc') || lo.startsWith('fd');
}

async function assertFetchable(rawUrl) {
  const parsed = new URL(rawUrl);
  if (!ALLOWED_SCHEMES.has(parsed.protocol)) throw new Error('scheme_not_allowed');
  const addrs = await dns.lookup(parsed.hostname, { all: true });
  if (addrs.length === 0) throw new Error('unresolvable_host');
  if (addrs.some((a) => isPrivateIp(a.address))) throw new Error('private_target');
  return parsed;
}

app.post('/api/notify', async (req, res) => {
  try {
    let target = await assertFetchable(req.body.webhookUrl);
    for (let hop = 0; hop < 3; hop++) {
      const resp = await fetch(target, {
        method: 'POST',
        redirect: 'manual', // 不自动跟随；每跳 Location 复验后再走
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ event: 'order.created' }),
      });
      const location = resp.headers.get('location');
      if (resp.status >= 300 && resp.status < 400 && location) {
        target = await assertFetchable(new URL(location, target).href);
        continue;
      }
      return res.json({ delivered: resp.ok, status: resp.status });
    }
    res.status(508).json({ error: 'too_many_redirects' });
  } catch (e) {
    res.status(400).json({ error: 'webhook_target_rejected' });
  }
});

app.listen(3000);
