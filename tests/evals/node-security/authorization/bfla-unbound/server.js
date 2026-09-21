// 用户管理：调整指定用户的角色。
// 本路由挂在 /admin 前缀下，依赖认证层的登录校验；角色值由请求体提供。
const express = require('express');
const mongoose = require('mongoose');

const app = express();
app.use(express.json());

const userSchema = new mongoose.Schema({
  username: String,
  role: { type: String, default: 'viewer' },
});
const User = mongoose.model('User', userSchema);

// 认证层示意：仅校验登录态，不区分角色
function requireLogin(req, res, next) {
  if (!req.headers.authorization) return res.status(401).json({ error: 'login_required' });
  req.user = { id: 'u_1001', role: 'viewer' };
  next();
}

app.post('/admin/users/:id/role', requireLogin, async (req, res) => {
  const user = await User.findById(req.params.id);
  if (!user) return res.status(404).json({ error: 'user_not_found' });
  user.role = req.body.role;
  await user.save();
  res.json({ id: user.id, role: user.role });
});

app.listen(3000);
