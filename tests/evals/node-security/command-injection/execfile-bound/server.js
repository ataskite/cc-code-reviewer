// 预览服务：对用户上传的图片生成缩略图。
// 文件名先收敛为 basename（剥离一切目录段），再以数组参数交给
// execFile 执行，全程不经 shell 解释。
const express = require('express');
const { execFile } = require('child_process');
const path = require('path');

const app = express();

app.get('/api/preview', (req, res) => {
  const raw = String(req.query.file || '');
  const safeName = path.basename(raw);

  if (safeName !== raw || safeName === '' || safeName.includes('\0')) {
    return res.status(400).json({ error: 'invalid_file_name' });
  }

  execFile('convert', [safeName, '-resize', '300x300', '/tmp/preview.png'], (err) => {
    if (err) return res.status(500).json({ error: 'convert_failed' });
    res.json({ preview: '/tmp/preview.png' });
  });
});

app.listen(3000);
