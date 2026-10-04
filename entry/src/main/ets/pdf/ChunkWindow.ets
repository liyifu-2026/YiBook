import { PageRange } from './RenderWindow';

// 长卷分块与渲染窗口（纯逻辑，自 view/ReaderView 抽出，便于单测守住硬约束）。
// 本文件必须保持纯逻辑，禁止 import @ohos / @kit 与 ArkUI。

// 单块画布高度上限（vp）。GPU 纹理上限约 4096-16384px，超限会**静默整块不渲染**：
// 24 页教材 16377vp(=32754px) 曾导致整卷空白且日志无错。滚动内容按此分块，只挂可见块。
export const CHUNK_MAX_VP = 1500;

// 窗口外判定余量（vp）：提前渲染，滚动时不露白
export const CHUNK_WINDOW_MARGIN = 300;

export interface PageChunk {
  top: number;
  height: number;
  pages: Array<number>;
  imgKey: number;
}

// 把页面槽位按 maxVp 分块：块是滚动内容里的直接子节点，
// 避免单个巨型 Stack 超过 GPU 纹理上限而整块不渲染。
// 规则为贪心累加：把后一页并入当前块后若「块底 - 块顶」仍不超限就并入，否则切块。
export function buildPageChunks(pageTops: Array<number>, slotHeights: Array<number>,
  maxVp: number): Array<PageChunk> {
  const out: Array<PageChunk> = [];
  let pages: Array<number> = [];
  let top = 0;
  let bottom = 0;
  const n = Math.min(pageTops.length, slotHeights.length);
  for (let i = 0; i < n; i++) {
    const pt = pageTops[i];
    const pb = pt + slotHeights[i];
    if (pages.length === 0) {
      top = pt;
      bottom = pb;
      pages.push(i);
    } else if (pb - top <= maxVp) {
      bottom = pb;
      pages.push(i);
    } else {
      out.push({ top: top, height: bottom - top, pages: pages, imgKey: 0 });
      top = pt;
      bottom = pb;
      pages = [i];
    }
  }
  if (pages.length > 0) {
    out.push({ top: top, height: bottom - top, pages: pages, imgKey: 0 });
  }
  return out;
}

// 重算可见块。关键：所有块都要出现在滚动内容里（窗口外的块保留高度但清空 pages），
// 否则滚动内容总高≈一屏，长卷根本滚不下去；占位块无绘制内容，不触发纹理上限。
// imgKey 只在「块内全部页就绪」时翻转：避免逐页到位各重建一次、
// 牵连同块 PageInkCanvas 反复重挂打断邻页书写。
export function visibleChunks(all: Array<PageChunk>, scrollY: number, viewportHeight: number,
  pageReady: Array<boolean>, margin: number): Array<PageChunk> {
  const vp = viewportHeight > 0 ? viewportHeight : 600;
  const vis: Array<PageChunk> = [];
  for (const ch of all) {
    const inWindow = ch.top < scrollY + vp + margin && ch.top + ch.height > scrollY - margin;
    let ready = 0;
    for (const p of ch.pages) {
      if (p >= 0 && p < pageReady.length && pageReady[p]) {
        ready++;
      }
    }
    vis.push({
      top: ch.top,
      height: ch.height,
      pages: inWindow ? ch.pages : [],
      imgKey: (inWindow && ready === ch.pages.length && ch.pages.length > 0) ? 1 : 0
    });
  }
  return vis;
}

// LRU 回收：返回应释放的页下标（窗外且当前已加载），让内存有界。
export function pagesToRelease(range: PageRange, loaded: Array<boolean>,
  margin: number): Array<number> {
  const out: Array<number> = [];
  if (range.first < 0 || range.last < 0) {
    return out;
  }
  for (let i = 0; i < loaded.length; i++) {
    if (!loaded[i]) {
      continue;
    }
    if (i < range.first - margin || i > range.last + margin) {
      out.push(i);
    }
  }
  return out;
}
