// 转换任务封装：负责拼装并执行资源转换命令。
const { exec } = require('child_process');

function buildCmd(input) {
  return 'convert ' + input + ' -resize 300x300 /tmp/preview.png';
}

function runTransformTask(input) {
  return new Promise((resolve, reject) => {
    exec(buildCmd(input), (err) => {
      if (err) reject(err);
      else resolve('/tmp/preview.png');
    });
  });
}

module.exports = { runTransformTask };
