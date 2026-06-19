'use strict';

// Issue #362: 同梱ロゴの四隅ピクセル色を検証するための依存ゼロ PNG デコーダ。
// npm パッケージ（pngjs 等）を足さず node 標準 zlib のみで IDAT を展開し、
// PNG フィルタ（0 None / 1 Sub / 2 Up / 3 Average / 4 Paeth）を逆適用して
// 四隅の RGB を取り出す。CI（ImageMagick 非依存・クロスプラットフォーム）で動かすため。
//
// 使い方: node tests/read-png-corners.js <png-path>
//   → "tl=r,g,b tr=r,g,b bl=r,g,b br=r,g,b" を 1 行で出力する（左上/右上/左下/右下）。

const fs = require('fs');
const zlib = require('zlib');

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

function decode(buf) {
  const sig = buf.slice(0, 8).toString('hex');
  if (sig !== '89504e470d0a1a0a') throw new Error('not a PNG');
  const width = buf.readUInt32BE(16);
  const height = buf.readUInt32BE(20);
  const bitDepth = buf[24];
  const colorType = buf[25];
  if (bitDepth !== 8) throw new Error('only 8-bit depth supported');
  // colortype 2=RGB(3ch) / 6=RGBA(4ch) のみ対応
  const channels = colorType === 2 ? 3 : colorType === 6 ? 4 : null;
  if (!channels) throw new Error('unsupported color type: ' + colorType);

  // IDAT チャンクを全て連結してから inflate する
  const idat = [];
  let off = 8;
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('ascii', off + 4, off + 8);
    if (type === 'IDAT') idat.push(buf.slice(off + 8, off + 8 + len));
    if (type === 'IEND') break;
    off += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));

  const bpp = channels; // bytes per pixel（8-bit 前提）
  const stride = width * bpp;
  const out = Buffer.alloc(height * stride);
  let prev = Buffer.alloc(stride); // 直前スキャンライン（最初は 0）
  let pos = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[pos++];
    const cur = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const rawByte = raw[pos++];
      const a = x >= bpp ? cur[x - bpp] : 0; // 左
      const b = prev[x]; // 上
      const c = x >= bpp ? prev[x - bpp] : 0; // 左上
      let val;
      switch (filter) {
        case 0: val = rawByte; break;
        case 1: val = rawByte + a; break;
        case 2: val = rawByte + b; break;
        case 3: val = rawByte + ((a + b) >> 1); break;
        case 4: val = rawByte + paeth(a, b, c); break;
        default: throw new Error('unknown filter: ' + filter);
      }
      cur[x] = val & 0xff;
    }
    cur.copy(out, y * stride);
    prev = cur;
  }

  const px = (x, y) => {
    const i = y * stride + x * bpp;
    return out[i] + ',' + out[i + 1] + ',' + out[i + 2];
  };
  return { width, height, px };
}

function main() {
  const path = process.argv[2];
  if (!path) {
    console.error('usage: node tests/read-png-corners.js <png-path>');
    process.exit(2);
  }
  const { width, height, px } = decode(fs.readFileSync(path));
  const m = 3; // 端から 3px 内側（PNG 端のアンチエイリアスを避ける）
  const tl = px(m, m);
  const tr = px(width - 1 - m, m);
  const bl = px(m, height - 1 - m);
  const br = px(width - 1 - m, height - 1 - m);
  process.stdout.write('tl=' + tl + ' tr=' + tr + ' bl=' + bl + ' br=' + br + '\n');
}

main();
