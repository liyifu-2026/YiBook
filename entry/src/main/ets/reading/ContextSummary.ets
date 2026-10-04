import { Chapter } from './ChapterModel';

// L1/L2 上下文补全（零 LLM 成本方案）：
// L1 = 章节目录摘要（章节标题即全书骨架，来自 M3 自动分章）；
// L2 = 本章节选（章首文字 + 范围）。LLM 精摘要留给 T3 摊销。

export function bookOutlineSummary(chapters: Array<Chapter>, maxChars: number): string {
  if (chapters.length === 0) {
    return '';
  }
  const head = `全书共${chapters.length}章：`;
  const parts: Array<string> = [];
  for (const c of chapters) {
    parts.push(`${c.title}(P${c.firstPage + 1})`);
  }
  let out = head + parts.join('、') + '。';
  while (out.length > maxChars && parts.length > 1) {
    parts.pop();
    out = head + parts.join('、') + `等${chapters.length}章。`;
  }
  return out;
}

export function chapterExcerpt(firstPage: number, lastPage: number, firstPageText: string,
  maxChars: number): string {
  const head = firstPageText.length > maxChars ? firstPageText.substring(0, maxChars) : firstPageText;
  return `本章P${firstPage + 1}-P${lastPage + 1}。章首摘录：${head}`;
}
