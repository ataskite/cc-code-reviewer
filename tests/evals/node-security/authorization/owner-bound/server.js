// 订单服务：登录用户按订单号查询订单详情。
// 查询条件同时并入订单属主（ownerId = 当前登录主体），不属于本人的
// 订单与不存在的订单同样按 404 处理。
const express = require('express');
const mongoose = require('mongoose');

const app = express();
app.use(express.json());

const orderSchema = new mongoose.Schema({
  ownerId: String,
  items: [String],
  total: Number,
});
const Order = mongoose.model('Order', orderSchema);

// 认证层示意：解析登录态
function requireLogin(req, res, next) {
  if (!req.headers.authorization) return res.status(401).json({ error: 'login_required' });
  req.user = { id: 'u_1001', role: 'member' };
  next();
}

app.get('/orders/:id', requireLogin, async (req, res) => {
  const order = await Order.findOne({ _id: req.params.id, ownerId: req.user.id });
  if (!order) return res.status(404).json({ error: 'not_found' });
  res.json(order);
});

app.listen(3000);
