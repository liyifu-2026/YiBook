// 卷坐标系墨迹模型（纯逻辑，禁止 import @ohos / @kit / ArkUI）。
//
// 为什么不能用旧的按页模型：旧模型把一笔锚在**某一页**上，渲染也是每页一个 Canvas，
// 于是笔迹天生在页边界被切断——用户明确要求「不同页码拼接的页面没有间隙，也能连续书写，
// 而不是碰到边缘就断掉笔迹」。根因不在渲染而在**数据模型**：笔迹锚在页上，就必然被页切开。
//
// 本模型把笔迹锚在**整卷坐标系**上（与 PdfView 的 pdf 坐标系同一套）：
//   卷 = 页在纵向依次拼接（页高 pageH + 页缝 gap），第 i 页的卷内顶边 = i*(pageH+gap)
// 一笔就是卷上的一串点，跨几页都行；需要用「页」的时候（AI 锚定、检索、进度）
// 再由坐标**换算**出来——方向是 卷→页，而不是 页→卷。
//
// 页缝 gap 必须显式建模：即使视觉上为 0，换算也要走同一套公式，否则页号会漂。

export interface DocPoint {
  x: number;
  y: number;
}

// 墨迹类型：0 = 普通墨（黑），1 = AI 液态彩（圈选提问）
export const INK_PLAIN = 0;
export const INK_AI = 1;

export interface DocStroke {
  id: number;
  points: Array<DocPoint>;
  color: string;
  width: number;
  kind: number;
}

export interface DocLayout {
  pageW: number;
  pageH: number;
  gap: number;
  count: number;
}

export interface DocBox {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

// 第 index 页在卷内的顶边 y
export function pageTopOf(layout: DocLayout, index: number): number {
  return index * (layout.pageH + layout.gap);
}

// 整卷高度（最后一页底边）
export function docHeightOf(layout: DocLayout): number {
  if (layout.count <= 0) {
    return 0;
  }
  return pageTopOf(layout, layout.count - 1) + layout.pageH;
}

// 卷坐标 -> 页号（落在页缝里时归到**上一页**，这样锚定不会凭空跳到下一页）
export function pageIndexAt(layout: DocLayout, y: number): number {
  if (layout.count <= 0) {
    return -1;
  }
  if (y <= 0) {
    return 0;
  }
  const stride = layout.pageH + layout.gap;
  if (stride <= 0) {
    return 0;
  }
  // idx = floor(y/stride) 按构造就满足 pageTop(idx) <= y，
  // 而页缝区间是 [pageTop+pageH, pageTop+stride)，所以**落在缝里时所属页就是 idx 自己**
  // （它正是缝上方那一页）。这里曾错误地再减 1，把缝里的点归到上上页，
  // 导致跨页笔迹被算成跨 3 页（单测当场抓住）。
  let idx = Math.floor(y / stride);
  if (idx >= layout.count) {
    return layout.count - 1;
  }
  if (idx < 0) {
    return 0;
  }
  return idx;
}

// 卷坐标 -> 页内 y（钳制到 [0, pageH]，页缝里的点贴到最近页边）
export function localYInPage(layout: DocLayout, y: number): number {
  const idx = pageIndexAt(layout, y);
  if (idx < 0) {
    return 0;
  }
  const local = y - pageTopOf(layout, idx);
  if (local < 0) {
    return 0;
  }
  if (local > layout.pageH) {
    return layout.pageH;
  }
  return local;
}

// 页内坐标 -> 卷坐标
export function docYOf(layout: DocLayout, index: number, localY: number): number {
  return pageTopOf(layout, index) + localY;
}

// 一笔覆盖到哪些页（按点序去重；跨页笔迹会得到连续多个页号）
// AI 锚定/检索用它：一笔跨 3 页时，这三页都该认为「这里有墨迹」。
export function pagesOfStroke(layout: DocLayout, s: DocStroke): Array<number> {
  const out: Array<number> = [];
  for (const p of s.points) {
    const idx = pageIndexAt(layout, p.y);
    if (idx >= 0 && out.indexOf(idx) < 0) {
      out.push(idx);
    }
  }
  out.sort((a: number, b: number): number => a - b);
  return out;
}

// 这笔是否跨了不止一页（= 是否属于「连续书写」的产物）
export function isCrossPage(layout: DocLayout, s: DocStroke): boolean {
  return pagesOfStroke(layout, s).length > 1;
}

// 主要锚点页：取笔画中点所在页，比首点更稳（起笔常带一点抖动/回勾）
export function anchorPageOf(layout: DocLayout, s: DocStroke): number {
  const n = s.points.length;
  if (n === 0) {
    return -1;
  }
  return pageIndexAt(layout, s.points[Math.floor(n / 2)].y);
}

export function boxOfStroke(s: DocStroke): DocBox {
  if (s.points.length === 0) {
    const empty: DocBox = { left: 0, top: 0, right: 0, bottom: 0 };
    return empty;
  }
  let left = s.points[0].x;
  let right = s.points[0].x;
  let top = s.points[0].y;
  let bottom = s.points[0].y;
  for (const p of s.points) {
    if (p.x < left) { left = p.x; }
    if (p.x > right) { right = p.x; }
    if (p.y < top) { top = p.y; }
    if (p.y > bottom) { bottom = p.y; }
  }
  const box: DocBox = { left: left, top: top, right: right, bottom: bottom };
  return box;
}

// 点到线段距离的平方（避免开方；比较用平方阈值）
function distSqToSegment(p: DocPoint, a: DocPoint, b: DocPoint): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lenSq = dx * dx + dy * dy;
  if (lenSq <= 0) {
    const ex = p.x - a.x;
    const ey = p.y - a.y;
    return ex * ex + ey * ey;
  }
  let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
  if (t < 0) { t = 0; }
  if (t > 1) { t = 1; }
  const cx = a.x + t * dx - p.x;
  const cy = a.y + t * dy - p.y;
  return cx * cx + cy * cy;
}

// 命中判定：笔宽的一半 + 手指容差。橡皮擦靠它。
export function strokeHits(s: DocStroke, p: DocPoint, tol: number): boolean {
  const r = tol + s.width / 2;
  const rSq = r * r;
  const n = s.points.length;
  if (n === 0) {
    return false;
  }
  if (n === 1) {
    const dx = p.x - s.points[0].x;
    const dy = p.y - s.points[0].y;
    return dx * dx + dy * dy <= rSq;
  }
  for (let i = 0; i + 1 < n; i++) {
    if (distSqToSegment(p, s.points[i], s.points[i + 1]) <= rSq) {
      return true;
    }
  }
  return false;
}

// 橡皮擦：返回被擦掉的那一笔（只擦最后一笔，符合「撤销/擦一笔」的手感）
export function findHitStroke(strokes: Array<DocStroke>, p: DocPoint,
  tol: number): number {
  for (let i = strokes.length - 1; i >= 0; i--) {
    if (strokeHits(strokes[i], p, tol)) {
      return i;
    }
  }
  return -1;
}

// 笔迹简化：丢弃与前一点距离小于 minDist 的点（手写采样点很密，存全量会撑爆存储）
export function simplify(points: Array<DocPoint>, minDist: number): Array<DocPoint> {
  const out: Array<DocPoint> = [];
  const minSq = minDist * minDist;
  for (const p of points) {
    if (out.length === 0) {
      out.push(p);
      continue;
    }
    const last = out[out.length - 1];
    const dx = p.x - last.x;
    const dy = p.y - last.y;
    if (dx * dx + dy * dy >= minSq) {
      out.push(p);
    }
  }
  // 末点总是保留，否则笔迹末端会被削掉一小截
  if (points.length > 0 && out.length > 0) {
    const last = points[points.length - 1];
    const kept = out[out.length - 1];
    if (kept.x !== last.x || kept.y !== last.y) {
      out.push(last);
    }
  }
  return out;
}

// ---- 持久化（纯字符串，不碰文件系统；由页面层落盘）----

// ArkTS 不允许无类型对象字面量，落盘行必须有显式结构。
// 字段名故意短：手写采样点很多，键名重复几千次会显著撑大文件。
interface StoredStroke {
  id: number;
  c: string;
  w: number;
  k: number;
  p: Array<number>;
}

export function strokesToJson(strokes: Array<DocStroke>): string {
  const rows: Array<StoredStroke> = [];
  for (const s of strokes) {
    const flat: Array<number> = [];
    for (const p of s.points) {
      flat.push(Math.round(p.x * 10) / 10);
      flat.push(Math.round(p.y * 10) / 10);
    }
    const row: StoredStroke = { id: s.id, c: s.color, w: s.width, k: s.kind, p: flat };
    rows.push(row);
  }
  return JSON.stringify(rows);
}

export function strokesFromJson(text: string): Array<DocStroke> {
  const out: Array<DocStroke> = [];
  if (text === '') {
    return out;
  }
  try {
    const rows = JSON.parse(text) as Array<StoredStroke>;
    for (const r of rows) {
      const flat = r.p;
      const pts: Array<DocPoint> = [];
      for (let i = 0; i + 1 < flat.length; i += 2) {
        pts.push({ x: flat[i], y: flat[i + 1] });
      }
      const s: DocStroke = {
        id: r.id,
        points: pts,
        color: r.c,
        width: r.w,
        kind: r.k
      };
      out.push(s);
    }
  } catch (err) {
    return [];
  }
  return out;
}
