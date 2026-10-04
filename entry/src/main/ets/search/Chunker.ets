// 章节感知切分的第一步：文本 → 带原始字符偏移的块。
// 契约：chunk.text === 原文.substring(charStart, charEnd)，锚点可回跳（铁律3）。

export interface TextChunk {
  text: string;
  charStart: number; // 含
  charEnd: number;   // 不含
}

interface LineSpan {
  start: number;
  end: number;
}

export function chunkText(text: string, targetChars: number, maxChars: number): Array<TextChunk> {
  const chunks: Array<TextChunk> = [];
  if (text.length === 0) {
    return chunks;
  }
  const spans: Array<LineSpan> = [];
  let lineStart = 0;
  for (let i = 0; i <= text.length; i++) {
    if (i === text.length || text[i] === '\n') {
      if (i > lineStart) {
        let s = lineStart;
        const e = i;
        while (e - s > maxChars) {
          const piece: LineSpan = { start: s, end: s + maxChars };
          spans.push(piece);
          s += maxChars;
        }
        const rest: LineSpan = { start: s, end: e };
        spans.push(rest);
      }
      lineStart = i + 1;
    }
  }
  let curStart = -1;
  let curEnd = -1;
  for (const sp of spans) {
    const mergedLen = curStart < 0 ? 0 : sp.end - curStart;
    if (curStart >= 0 && mergedLen > targetChars) {
      pushChunk(chunks, text, curStart, curEnd);
      curStart = -1;
    }
    if (curStart < 0) {
      curStart = sp.start;
      curEnd = sp.end;
    } else {
      curEnd = sp.end;
    }
  }
  if (curStart >= 0) {
    pushChunk(chunks, text, curStart, curEnd);
  }
  return chunks;
}

function pushChunk(chunks: Array<TextChunk>, text: string, start: number, end: number): void {
  const c: TextChunk = { text: text.substring(start, end), charStart: start, charEnd: end };
  chunks.push(c);
}
