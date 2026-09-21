// 文件服务：按名称读取 /data 目录下的共享附件并返回给调用方。
const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const DATA_ROOT = '/data';

app.get('/files/:name', (req, res) => {
  const full = path.join(DATA_ROOT, req.params.name);
  const content = fs.readFileSync(full, 'utf8');
  res.type('text/plain').send(content);
});

app.listen(3000);
