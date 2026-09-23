// 通知服务（不安全样例）：DNS 解析结果做了完整私网校验，但校验后仍按
// 域名发起 fetch——fetch 会重新解析 DNS，攻击者控制权威解析时可先返回公网
// IP 通过校验、正式连接时返回 169.254.169.254（DNS rebinding / TOCTOU）。
const express = require('express');
const dns = require('dns').promises;
const net = require('net');

const app = express();
app.use(express.json());

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

app.post('/api/notify', async (req, res) => {
  try {
    const target = new URL(req.body.webhookUrl);
    if (target.protocol !== 'https:') throw new Error('scheme');
    const addrs = await dns.lookup(target.hostname, { all: true }); // 校验用的解析
    if (addrs.length === 0 || addrs.some((a) => isPrivateIp(a.address))) throw new Error('private');
    // 缺陷：连接仍按域名 → fetch 内部再次解析 DNS（校验与连接脱节）
    const resp = await fetch(target, { method: 'POST', redirect: 'manual' });
    res.json({ delivered: resp.ok, status: resp.status });
  } catch (e) {
    res.status(400).json({ error: 'webhook_target_rejected' });
  }
});

app.listen(3000);
