import { pageAt } from './ContinuousLayout';

export interface PageRange {
  first: number;
  last: number;
}

// 滚动位置的唯一取值口径。
//
// 坑（实证踩过，代价是「整本书只能看第一页」）：`Scroll.onScroll` 的第二个入参是
// **相对上一帧的增量**，不是绝对滚动位置。把它当绝对位置用，scrollY 就恒等于
// 「最后一帧移动的那一点点」（真机实测 1.2~2.0vp），渲染窗口于是永远算在 y≈0：
// 整卷只有第一块有内容、其余是等高空占位，用户看到的就是「往下一片空白 + 页码恒为 P1」。
//
// 绝对位置只认滚动容器自己的报告（`scroller.currentOffset().yOffset`，实测在 onScroll
// 回调内已是新值）。只有容器还报不出位置时，才用增量累加兜底——**绝不直接把增量当位置**。
export function absoluteScrollOffset(reportedAbs: number, prevAbs: number, delta: number): number {
  if (Number.isFinite(reportedAbs) && reportedAbs >= 0) {
    return reportedAbs;
  }
  const fallback = prevAbs + delta;
  return Number.isFinite(fallback) && fallback >= 0 ? fallback : prevAbs;
}

export function renderWindow(offsets: Array<number>, scrollY: number, viewportHeight: number,
  prerender: number): PageRange {
  const n = offsets.length;
  if (n === 0) {
    const empty: PageRange = { first: -1, last: -1 };
    return empty;
  }
  let first = pageAt(offsets, scrollY) - prerender;
  let last = pageAt(offsets, scrollY + viewportHeight) + prerender;
  if (first < 0) {
    first = 0;
  }
  if (last > n - 1) {
    last = n - 1;
  }
  const range: PageRange = { first: first, last: last };
  return range;
}
