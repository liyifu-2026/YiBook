import { OutlineMarker } from './ChapterModel';

// 扫描书管线（决策 #15）T2：视觉 LLM 按约定格式读目录页后，
// 由本解析器把目录文本转为章节标记（只认「第N章/部分/讲」级，小节忽略）。

function toHalfWidth(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    let code = s.charCodeAt(i);
    if (code === 0x3000) {
      code = 0x20; // 全角空格
    } else if (code >= 0xFF10 && code <= 0xFF19) {
      code = code - 0xFEE0; // 全角数字
    }
    out += String.fromCharCode(code);
  }
  return out;
}

export function markersFromTocText(tocText: string): Array<OutlineMarker> {
  const markers: Array<OutlineMarker> = [];
  const lines = tocText.split(/\r?\n/);
  const chapterRe = new RegExp('^第\\s*(\\d+)\\s*([章部分讲])\\s*(.*)$');
  const leaderRe = new RegExp('[\\s·．.…_＿\\-—]*(\\d{1,3})\\s*$');
  for (const raw of lines) {
    const line = toHalfWidth(raw).trim();
    const m = chapterRe.exec(line);
    if (m === null) {
      continue;
    }
    const rest = m[2 + 1];
    const pm = leaderRe.exec(rest);
    if (pm === null) {
      continue; // 无页码，无法锚定
    }
    const page = parseInt(pm[1], 10);
    let title = rest.substring(0, rest.length - pm[0].length);
    title = title.replace(/[\s·．.…_＿\-—]+$/g, '').trim();
    if (title === '') {
      continue;
    }
    const marker: OutlineMarker = { title: `第${m[1]}${m[2]} ${title}`, page: page };
    markers.push(marker);
  }
  // 目录契约：按页码升序（VLM 读取顺序不可靠，排序后交给 chaptersFromOutline）
  markers.sort((a, b) => a.page - b.page);
  return markers;
}
