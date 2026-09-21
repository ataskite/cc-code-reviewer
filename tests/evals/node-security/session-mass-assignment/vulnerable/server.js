// 资料编辑接口：把用户提交的个人资料合并进服务端会话。
// 提交字段不固定，因此逐键写入，前端加什么字段会话就同步什么字段。
const express = require('express');
const session = require('express-session');

const app = express();
app.use(express.json());
app.use(session({ secret: 'fixture-placeholder', resave: false, saveUninitialized: false }));

app.post('/api/profile', (req, res) => {
  for (let k in req.body) {
    req.session[k] = req.body[k];
  }
  res.json({ updated: true });
});

app.get('/api/me', (req, res) => {
  if (req.session.isAdmin || req.session.role === 'admin') {
    return res.json({ adminPanel: true });
  }
  res.json({ profile: req.session });
});

app.listen(3000);
