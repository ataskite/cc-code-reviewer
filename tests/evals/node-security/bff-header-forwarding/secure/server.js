// BFF 转发层：向内网订单服务递交请求。
// 上游请求头按显式白名单逐头构造；身份头不采纳客户端值，由服务端
// session 重新生成；hop-by-hop 头一律剥离。
const express = require('express');
const axios = require('axios');

const app = express();
app.use(express.json());

const UPSTREAM = 'http://orders-svc:8080/api/orders';

// 与身份无关、允许透传的展示类头
const HEADER_ALLOWLIST = ['accept-language', 'x-request-id'];

// RFC 定义的逐跳头，转发前剥离
const HOP_BY_HOP = [
  'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
  'te', 'trailer', 'transfer-encoding', 'upgrade',
];

// 服务端 session（示意实现，客户端不可伪造）
async function loadSession() {
  return { userId: 'u_1001' };
}

app.post('/api/orders', async (req, res) => {
  const session = await loadSession(req);

  const upstreamHeaders = {};
  for (const name of HEADER_ALLOWLIST) {
    if (req.headers[name] !== undefined) upstreamHeaders[name] = req.headers[name];
  }
  for (const name of HOP_BY_HOP) delete upstreamHeaders[name];

  // 身份头由 BFF 侧认证结果重新生成，不透传客户端值
  upstreamHeaders['x-user-id'] = session.userId;

  const resp = await axios.post(UPSTREAM, req.body, { headers: upstreamHeaders });
  res.status(resp.status).json(resp.data);
});

app.listen(3000);
