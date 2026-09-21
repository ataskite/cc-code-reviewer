// 资料编辑接口：把用户提交的个人资料合并进服务端会话。
// 提交体先过 joi schema（unknown(false) 拒绝一切白名单外字段），
// 会话字段再按白名单逐字段显式赋值；权限类字段不属于可编辑资料。
const express = require('express');
const session = require('express-session');
const Joi = require('joi');

const app = express();
app.use(express.json());
app.use(session({ secret: 'fixture-placeholder', resave: false, saveUninitialized: false }));

const PROFILE_SCHEMA = Joi.object({
  displayName: Joi.string().max(64).required(),
  locale: Joi.string().valid('zh-CN', 'en-US'),
}).unknown(false);

app.post('/api/profile', (req, res) => {
  const { value, error } = PROFILE_SCHEMA.validate(req.body);
  if (error) return res.status(400).json({ error: 'invalid_profile' });

  if (value.displayName !== undefined) req.session.displayName = value.displayName;
  if (value.locale !== undefined) req.session.locale = value.locale;

  res.json({ updated: true });
});

app.get('/api/me', (req, res) => {
  res.json({ displayName: req.session.displayName, locale: req.session.locale });
});

app.listen(3000);
