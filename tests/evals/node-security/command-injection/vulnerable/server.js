// 预览服务：对用户上传的图片生成缩略图。
// 文件名来自查询参数，直接拼进 convert 命令行生成预览。
const express = require('express');
const { exec } = require('child_process');

const app = express();

app.get('/api/preview', (req, res) => {
  const file = req.query.file;

  exec('convert ' + file + ' -resize 300x300 /tmp/preview.png', (err) => {
    if (err) return res.status(500).json({ error: 'convert_failed' });
    res.json({ preview: '/tmp/preview.png' });
  });
});

app.listen(3000);
