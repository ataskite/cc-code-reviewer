// 订单服务：登录用户按订单号查询订单详情。
// 假定认证层已解析出 req.user（登录态），本路由只依赖登录即可取单。
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
  const order = await Order.findById(req.params.id);
  if (!order) return res.status(404).json({ error: 'not_found' });
  res.json(order);
});

app.listen(3000);
