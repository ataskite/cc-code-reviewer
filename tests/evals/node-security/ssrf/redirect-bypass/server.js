// 通知服务：向租户配置的 webhook 地址投递事件。
// 首次请求前校验目标 host 是否为公网地址；为兼容部分 webhook 供应商的
// 跳转登录流程，出站客户端允许跟随重定向。
const express = require('express');
const axios = require('axios');
const dns = require('dns').promises;

const app = express();
app.use(express.json());

async function isPublicHost(hostname) {
  const addrs = await dns.lookup(hostname, { all: true });
  return addrs.every((a) => !a.address.startsWith('10.') && !a.address.startsWith('169.254.'));
}

app.post('/api/notify', async (req, res) => {
  const { webhookUrl } = req.body;

  const initial = new URL(webhookUrl);
  if (initial.protocol !== 'https:' || !(await isPublicHost(initial.hostname))) {
    return res.status(400).json({ error: 'webhook_host_not_allowed' });
  }

  const resp = await axios.post(webhookUrl, { event: 'order.created' }, {
    maxRedirects: 5,
    headers: { 'content-type': 'application/json' },
  });

  res.json({ delivered: true, status: resp.status });
});

app.listen(3000);
