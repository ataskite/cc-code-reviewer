// 预览服务：对外只暴露一个通用的资源转换入口。
// 转换任务的执行细节封装在 tasks/resize.js 中。
const express = require('express');
const { runTransformTask } = require('./tasks/resize');

const app = express();

app.get('/api/preview', async (req, res) => {
  try {
    const output = await runTransformTask(String(req.query.file || ''));
    res.json({ preview: output });
  } catch (e) {
    res.status(500).json({ error: 'transform_failed' });
  }
});

app.listen(3000);
