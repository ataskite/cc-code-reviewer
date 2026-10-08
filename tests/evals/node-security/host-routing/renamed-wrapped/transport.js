const http = require('node:http');
function assemble(packet) {
  return { method: 'POST', headers: { ...packet.metadata } };
}
function relay(packet, res) {
  const call = http.request('http://ingress.example.test/public/preview', assemble(packet),
    upstream => upstream.pipe(res));
  call.on('error', () => res.sendStatus(502));
  call.end(JSON.stringify({ query: packet.value }));
}
module.exports = { relay };
