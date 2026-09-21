// BFF 转发层：把前端请求原样递交给内网订单服务。
// 为了让上游拿到完整上下文，客户端请求头整体携带在出站请求上。
const express = require('express');
const axios = require('axios');

const app = express();
app.use(express.json());

// 内网上游（虚构服务名）
const UPSTREAM = 'http://orders-svc:8080/api/orders';

app.post('/api/orders', async (req, res) => {
  const resp = await axios.post(UPSTREAM, req.body, { headers: req.headers });
  res.status(resp.status).json(resp.data);
});

app.listen(3000);
