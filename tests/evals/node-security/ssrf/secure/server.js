// 通知服务：向租户配置的 webhook 地址投递事件。
// 出站目标必须通过完整校验并「绑定到实际连接」：
// 1) scheme 白名单（仅 https）；
// 2) DNS 解析一次，全部解析地址校验（IPv4 私网/CGNAT/组播 + IPv6 loopback/
//    link-local fe80::/10/ULA fc00::/7/IPv4-mapped/NAT64/6to4）；
// 3) 已校验 IP 直接作为连接目标（DNS 不再二次解析，消除 DNS rebinding/TOCTOU）；
//    TLS 通过 servername 绑定原始主机名（SNI + 证书主机校验不受 IP 连接影响）；
// 4) 重定向手动跟随：每一跳 Location 重新过同一套「解析→校验→绑定」流程。
// 参考：OWASP SSRF Prevention Cheat Sheet（IP 归一化/DNS 风险/应用层控制）。
const express = require('express');
const dns = require('dns');
const https = require('https');
const net = require('net');

const app = express();
app.use(express.json());

const ALLOWED_SCHEMES = new Set(['https:']);
const HOP_LIMIT = 3;

// 归一化：IPv4-mapped IPv6（::ffff:a.b.c.d 与 ::ffff:hex:hex）→ 提取内嵌 IPv4，
// 避免 mapped 形态绕过 IPv4 段校验。
function normalizeIp(ip) {
  const v = String(ip).toLowerCase().replace(/^\[|\]$/g, '');
  if (net.isIPv4(v)) return v;
  if (!net.isIPv6(v)) return null;
  // WHATWG URL canonicalizes expanded/mixed IPv6 forms, e.g.
  // 0:0:0:0:0:ffff:7f00:1 -> ::ffff:7f00:1.
  const canonical = new URL(`http://[${v}]/`).hostname.slice(1, -1).toLowerCase();
  const m2 = /^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(canonical);
  if (m2) {
    const hi = parseInt(m2[1], 16);
    const lo = parseInt(m2[2], 16);
    return `${(hi >> 8) & 255}.${hi & 255}.${(lo >> 8) & 255}.${lo & 255}`;
  }
  return canonical;
}

function isPrivateIp(rawIp) {
  const ip = normalizeIp(rawIp);
  if (ip === null) return true; // DNS 应只返回 IP；解析异常按拒绝处理
  if (net.isIPv4(ip)) {
    const o = ip.split('.').map(Number);
    if (o.length !== 4 || o.some((x) => !Number.isInteger(x) || x < 0 || x > 255)) return true; // 畸形按私网拒绝
    const [a, b] = o;
    return (
      a === 0 ||                                   // 0.0.0.0/8「本网络」
      a === 10 ||                                  // 10/8 私网
      a === 127 ||                                 // 127/8 loopback
      (a === 100 && b >= 64 && b <= 127) ||        // 100.64/10 CGNAT
      (a === 169 && b === 254) ||                  // 169.254/16 链路本地/云元数据
      (a === 172 && b >= 16 && b <= 31) ||         // 172.16/12 私网
      (a === 192 && b === 0 && o[2] === 0) ||      // 192.0.0/24 协议分配
      (a === 192 && b === 0 && o[2] === 2) ||      // 192.0.2/24 文档网段
      (a === 192 && b === 88 && o[2] === 99) ||   // 192.88.99/24 过渡网段
      (a === 192 && b === 168) ||                  // 192.168/16 私网
      (a === 198 && (b === 18 || b === 19)) ||     // 198.18/15 基准测试网段
      (a === 198 && b === 51 && o[2] === 100) ||   // 198.51.100/24 文档网段
      (a === 203 && b === 0 && o[2] === 113) ||    // 203.0.113/24 文档网段
      a >= 224                                    // 组播/保留/广播段（含 240/4）
    );
  }
  // Allow only global-unicast 2000::/3, with known special-purpose ranges denied.
  const words = ip.split(':').filter(Boolean);
  const first = parseInt(words[0] || '0', 16);
  const second = parseInt(words[1] || '0', 16);
  const globalUnicast = first >= 0x2000 && first <= 0x3fff;
  const specialPurpose =
    (first === 0x2001 && (second <= 0x01ff || second === 0x0020 || second === 0x0db8)) || // protocol, ORCHID, docs
    first === 0x2002; // 6to4 embeds an IPv4 destination
  return !globalUnicast || specialPurpose;
}

function reject(res) {
  if (res.headersSent || res.writableEnded) return;
  res.status(400).json({ error: 'webhook_target_rejected' });
}

// 校验并连接：解析一次 → 全地址校验 → 用已校验 IP 发起 https 连接。
// servername 保持原始主机名，SNI 与证书主机校验均按域名进行（不放行 IP 证书）。
function requestPinned(parsed, res, done, hop) {
  const dnsHost = parsed.hostname.replace(/^\[|\]$/g, '');
  if (!ALLOWED_SCHEMES.has(parsed.protocol) || (parsed.port && parsed.port !== '443') || parsed.username || parsed.password) {
    return reject(res);
  }
  dns.lookup(dnsHost, { all: true }, (err, addrs) => {
    if (err || !addrs || addrs.length === 0) return reject(res);
    for (const a of addrs) {
      if (isPrivateIp(a.address)) return reject(res); // 任一私网地址即整体拒绝
    }
    const pinnedIp = addrs[0].address;
    const req = https.request(
      {
        host: pinnedIp,                  // 连接目标 = 已校验 IP（DNS 不再二次解析）
        family: net.isIP(pinnedIp),      // 连接时只使用 DNS 校验得到的地址族/IP
        port: 443,
        servername: net.isIP(dnsHost) ? undefined : dnsHost, // 域名 TLS 校验绑定原始主机名
        path: parsed.pathname + parsed.search,
        method: 'POST',
        headers: { host: parsed.host, 'content-type': 'application/json' },
      },
      (upstream) => {
        // Node https.request 不自动跟随重定向：每跳 Location 重新校验
        if (upstream.statusCode >= 300 && upstream.statusCode < 400 && upstream.headers.location) {
          upstream.resume();
          if (hop + 1 > HOP_LIMIT) return reject(res);
          let next;
          try {
            next = new URL(upstream.headers.location, parsed);
          } catch (e) {
            return reject(res);
          }
          if (!ALLOWED_SCHEMES.has(next.protocol)) return reject(res);
          return requestPinned(next, res, done, hop + 1);
        }
        const status = upstream.statusCode;
        upstream.resume(); // 如响应体无需使用，直接丢弃，避免无界缓冲
        upstream.on('end', () => done({ status }));
      }
    );
    req.setTimeout(5000, () => req.destroy(new Error('upstream_timeout')));
    req.on('error', () => reject(res));
    req.write(JSON.stringify({ event: 'order.created' }));
    req.end();
  });
}

app.post('/api/notify', (req, res) => {
  let target;
  try {
    target = new URL(req.body.webhookUrl);
  } catch (e) {
    return reject(res);
  }
  if (!ALLOWED_SCHEMES.has(target.protocol)) return reject(res);
  requestPinned(target, res, (delivered) => res.json({ delivered: delivered.status < 400, status: delivered.status }), 0);
});

app.listen(3000);
