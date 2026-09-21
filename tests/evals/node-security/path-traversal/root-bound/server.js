// 文件服务：按名称读取 /data 目录下的共享附件并返回给调用方。
// 文件名先收敛为 basename，再 resolve 到根目录并校验结果仍位于根内，
// 越界一律拒绝。
const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const DATA_ROOT = '/data';

app.get('/files/:name', (req, res) => {
  try {
    const full = path.resolve(DATA_ROOT, path.basename(req.params.name));
    if (!full.startsWith(DATA_ROOT + path.sep)) {
      throw new Error('path_out_of_root');
    }
    const content = fs.readFileSync(full, 'utf8');
    res.type('text/plain').send(content);
  } catch (e) {
    res.status(403).json({ error: 'path_out_of_root' });
  }
});

app.listen(3000);
