// BFF 转发层：将请求递交给核心服务的通用管道。
// 路由层只依赖 pipeToCoreSvc 一个入口，出站细节封装在 util 层。
const express = require('express');
const axios = require('axios');

const app = express();
app.use(express.json());

const CORE_SVC = 'http://core-svc:8080/v1/orders';

// util 第一层：从入站请求提取 meta（保持完整，不拆字段）
function pickMeta(headers) {
  return headers;
}

// util 第二层：装饰出站配置
function decorate(outboundOpts) {
  return Object.assign({ timeout: 5000 }, outboundOpts);
}

async function pipeToCoreSvc(req, payload) {
  const meta = pickMeta(req.headers);
  const opts = decorate({ headers: meta });
  return axios.post(CORE_SVC, payload, { headers: opts.headers, timeout: opts.timeout });
}

app.post('/api/orders', async (req, res) => {
  const resp = await pipeToCoreSvc(req, req.body);
  res.status(resp.status).json(resp.data);
});

app.listen(3000);
