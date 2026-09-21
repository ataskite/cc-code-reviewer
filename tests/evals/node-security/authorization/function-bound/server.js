// 用户管理：调整指定用户的角色。
// 管理动作在执行前依次经过登录校验与角色校验中间件；校验不通过
// （未登录 401 / 角色不符 403）直接拒绝，角色值再经白名单收敛。
const express = require('express');
const mongoose = require('mongoose');

const app = express();
app.use(express.json());

const userSchema = new mongoose.Schema({
  username: String,
  role: { type: String, default: 'viewer' },
});
const User = mongoose.model('User', userSchema);

const ASSIGNABLE_ROLES = ['viewer', 'operator', 'admin'];

// 认证层示意：解析登录态
function requireLogin(req, res, next) {
  if (!req.headers.authorization) return res.status(401).json({ error: 'login_required' });
  req.user = { id: 'u_1001', role: 'admin' };
  next();
}

// 角色校验：在动作前生效，异常/缺失一律拒绝（deny by default）
function requireRole(role) {
  return function (req, res, next) {
    if (!req.user || req.user.role !== role) return res.status(403).json({ error: 'forbidden' });
    next();
  };
}

app.post('/admin/users/:id/role', requireLogin, requireRole('admin'), async (req, res) => {
  if (!ASSIGNABLE_ROLES.includes(req.body.role)) {
    return res.status(400).json({ error: 'invalid_role' });
  }
  const user = await User.findById(req.params.id);
  if (!user) return res.status(404).json({ error: 'user_not_found' });
  user.role = req.body.role;
  await user.save();
  res.json({ id: user.id, role: user.role });
});

app.listen(3000);
