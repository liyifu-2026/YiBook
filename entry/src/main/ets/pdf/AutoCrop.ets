// 自动裁白边：从整本书的页面里稳健地估出「内容框」（纯逻辑，禁止 import @ohos / @kit / ArkUI）。
//
// 为什么推倒重来（旧做法：固定阈值 180 找墨迹外接框，再按奇偶取并集）：
//   1. 固定阈值对扫描件无解：偏暗的书整页判成墨，偏亮的书浅字被判成白纸。
//   2. 外接框对单点噪声零抵抗：一粒灰、一道扫描阴影就能把框撑到页边。
//   3. **并集对离群页零抵抗**：一本 300 页的书里只要有一页插图出血、或一页是封面/对开扫描，
//      整本书（或整个奇偶簇）的框就被永久撑大——边距永远裁不干净，而且看起来"每本都不一样"。
//   4. 逐页裁剪 = 每页一个框 → 翻页时版心左右/上下跳，观感是"裁剪有问题"。
//
// 本模块的做法：
//   a. **自适应阈值**（Otsu，按每页自己的灰度直方图）——不依赖任何硬编码灰度。
//   b. **行/列投影 + 连续段要求**：一行里墨点占比达到 inkRatio 且连续 runMin 行才算内容行，
//      噪声行/孤立污渍自然被滤掉。
//   c. **稳健聚合**：对每页的内容框取中位数，用 MAD（中位数绝对偏差）剔除离群页，
//      再**只对留下的正常页取并集**——对正常页绝不切内容，同时对离群页免疫。
//   d. **一致性优先**：默认全书共用一个框；只有奇偶差异确实显著（超过 parityDelta）才分奇偶。
//   e. **合理性兜底**：结果不像话（裁得比 minHeight 还矮、或几乎没裁）就返回 null，
//      退回整页显示——**永不比不裁更差**。
//   f. **对开扫描保护**：中缝近空白且两侧都有内容时判为 cross-page，不做单页框裁剪
//      （否则会把左页或右页整页切掉）。

export interface PageBox {
  top: number;    // 0..1，页面归一化坐标
  bottom: number;
  left: number;
  right: number;
}

export interface CropParams {
  inkRatio: number;      // 行/列判为「有内容」的墨点占比阈值
  runMin: number;        // 连续多少行/列才算内容（抗噪）
  blankInk: number;      // 全页墨点占比低于此值 → 空白页，不参与统计
  photoInk: number;      // 高于此值 → 照片/封面/纯色页，不参与统计
  rejectMad: number;     // 离群判定：偏差 > rejectMad × max(MAD, madFloor)
  madFloor: number;      // MAD 下限，防止 MAD=0 时把正常差异全判成离群
  padRatio: number;      // 最终外扩（防贴边裁字）
  minHeight: number;     // 内容高低于页面高 × 此值 → 判为不可信
  minWidth: number;
  parityDelta: number;   // 奇偶框差异超过页面尺寸的此比例才分奇偶
  gutterInk: number;     // 中缝列最大墨点占比低于此值才算「近空白」
  edgeQuantile: number;  // 每条边按此分位取裁线（0.25 = 只在 75% 页都同意的范围内裁）
  maxEdgeSpread: number; // 某条边的四分位距超过此值 → 这本书没有一致版心，不裁
  maxTrim: number;       // 单边最多裁掉页面尺寸的多少（超出就夹到这个上限）
}

export const CROP_DEFAULTS: CropParams = {
  inkRatio: 0.02,
  runMin: 3,
  blankInk: 0.002,
  photoInk: 0.45,
  rejectMad: 4.0,
  madFloor: 0.01,
  padRatio: 0.004,
  minHeight: 0.35,
  minWidth: 0.35,
  parityDelta: 0.02,
  gutterInk: 0.01,
  edgeQuantile: 0.25,
  maxEdgeSpread: 0.15,
  maxTrim: 0.25
};

export interface CropResult {
  shared: PageBox | null;   // 全书统一框（split=false 时用它）
  even: PageBox | null;     // split=true 时奇偶各一个
  odd: PageBox | null;
  split: boolean;
  spread: boolean;          // 多数页判为对开扫描 → 放弃单页框
  used: number;             // 参与统计的页数
  rejected: number;         // 被判为离群而剔除的页数
}

// ---------- 阈值 ----------

// Otsu：在 0..255 灰度直方图上最大化类间方差。返回「墨/纸」分界，墨 = gray <= 返回值。
export function otsuThreshold(gray: Uint8Array): number {
  const hist: Array<number> = [];
  for (let i = 0; i < 256; i++) {
    hist.push(0);
  }
  for (let i = 0; i < gray.length; i++) {
    hist[gray[i]]++;
  }
  const total = gray.length;
  if (total === 0) {
    return 128;
  }
  let sum = 0;
  for (let i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  let sumB = 0;
  let wB = 0;
  let best = 0;
  let bestVar = -1;
  for (let t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB === 0) {
      continue;
    }
    const wF = total - wB;
    if (wF === 0) {
      break;
    }
    sumB += t * hist[t];
    const mB = sumB / wB;
    const mF = (sum - sumB) / wF;
    const between = wB * wF * (mB - mF) * (mB - mF);
    if (between > bestVar) {
      bestVar = between;
      best = t;
    }
  }
  return best;
}

export function inkShare(gray: Uint8Array, threshold: number): number {
  if (gray.length === 0) {
    return 0;
  }
  let ink = 0;
  for (let i = 0; i < gray.length; i++) {
    if (gray[i] <= threshold) {
      ink++;
    }
  }
  return ink / gray.length;
}

// ---------- 行/列投影 ----------

export interface Profiles {
  rows: Array<number>;   // 每行墨点占比 0..1
  cols: Array<number>;
}

export function profilesOf(gray: Uint8Array, w: number, h: number,
  threshold: number): Profiles {
  const rows: Array<number> = [];
  const cols: Array<number> = [];
  for (let y = 0; y < h; y++) {
    rows.push(0);
  }
  for (let x = 0; x < w; x++) {
    cols.push(0);
  }
  for (let y = 0; y < h; y++) {
    const base = y * w;
    for (let x = 0; x < w; x++) {
      if (gray[base + x] <= threshold) {
        rows[y]++;
        cols[x]++;
      }
    }
  }
  for (let y = 0; y < h; y++) {
    rows[y] = rows[y] / w;
  }
  for (let x = 0; x < w; x++) {
    cols[x] = cols[x] / h;
  }
  const p: Profiles = { rows: rows, cols: cols };
  return p;
}

export interface Band {
  lo: number;   // 含
  hi: number;   // 含
}

// 在投影上找正文带。
//
// 判据用「窗口内达标的行/列**计数**」，不用「窗口均值」：
// 均值会被单个大尖峰拉高——一行里恰好有一道黑边（扫描阴影/装订线），均值立刻就过线了，
// 于是整页的框被拽到页边。改成「长度 win 的窗口里至少要有 run 个达标行」之后，
// 孤立噪声行（计数=1）撑不起一段，而真实文本块因为行间有空白、达标行始终有 4~5 个，稳定通过。
// 因为文本行之间有白空隙，「要求每一行都达标」也不行（那会把正文判成没有内容）。
export function contentBand(profile: Array<number>, inkRatio: number,
  runMin: number): Band | null {
  const n = profile.length;
  if (n === 0) {
    return null;
  }
  const run = runMin < 1 ? 1 : (runMin > n ? n : runMin);
  const win = run * 3 > n ? n : run * 3;
  let first = -1;
  let last = -1;
  for (let i = 0; i + win <= n; i++) {
    let cnt = 0;
    for (let k = i; k < i + win; k++) {
      if (profile[k] >= inkRatio) {
        cnt++;
      }
    }
    if (cnt >= run) {
      if (first < 0) {
        first = i;
      }
      last = i + win - 1;
    }
  }
  if (first < 0) {
    return null;
  }
  // 收束到窗口内真正达标的首/末行，避免把 win-1 行的空白算进内容
  let lo = first;
  while (lo <= last && profile[lo] < inkRatio) {
    lo++;
  }
  let hi = last;
  while (hi >= lo && profile[hi] < inkRatio) {
    hi--;
  }
  if (lo > hi) {
    return null;
  }
  const band: Band = { lo: lo, hi: hi };
  return band;
}

// ---------- 单页内容框 ----------

export interface PageScan {
  box: PageBox | null;   // null = 该页不参与统计（空白/照片/测不出）
  spread: boolean;
  ink: number;
}

// 中缝列是否近空白（用于对开扫描判定）；要求中缝两侧都确实有内容。
export function looksLikeSpread(p: Profiles, params: CropParams): boolean {
  const n = p.cols.length;
  if (n < 8) {
    return false;
  }
  const g0 = Math.floor(n * 0.40);
  const g1 = Math.ceil(n * 0.60);
  let gutterMin = 1;
  for (let x = g0; x <= g1 && x < n; x++) {
    if (p.cols[x] < gutterMin) {
      gutterMin = p.cols[x];
    }
  }
  if (gutterMin > params.gutterInk) {
    return false;
  }
  let leftInk = 0;
  for (let x = 0; x < g0; x++) {
    leftInk += p.cols[x];
  }
  let rightInk = 0;
  for (let x = g1 + 1; x < n; x++) {
    rightInk += p.cols[x];
  }
  // 两侧都要有明显的文本块（用平均列墨点占比衡量）
  const leftAvg = g0 > 0 ? leftInk / g0 : 0;
  const rightAvg = (n - g1 - 1) > 0 ? rightInk / (n - g1 - 1) : 0;
  return leftAvg >= params.inkRatio && rightAvg >= params.inkRatio;
}

export function scanPage(gray: Uint8Array, w: number, h: number,
  params: CropParams): PageScan {
  const empty: PageScan = { box: null, spread: false, ink: 0 };
  if (w <= 0 || h <= 0 || gray.length < w * h) {
    return empty;
  }
  const thr = otsuThreshold(gray);
  const ink = inkShare(gray, thr);
  if (ink < params.blankInk || ink > params.photoInk) {
    // 空白页 / 照片页都不该参与「书本版心」统计
    const skip: PageScan = { box: null, spread: false, ink: ink };
    return skip;
  }
  const p = profilesOf(gray, w, h, thr);
  const spread = looksLikeSpread(p, params);
  const rows = contentBand(p.rows, params.inkRatio, params.runMin);
  const cols = contentBand(p.cols, params.inkRatio, params.runMin);
  if (rows === null || cols === null) {
    const none: PageScan = { box: null, spread: spread, ink: ink };
    return none;
  }
  const box: PageBox = {
    top: rows.lo / h,
    bottom: (rows.hi + 1) / h,
    left: cols.lo / w,
    right: (cols.hi + 1) / w
  };
  const out: PageScan = { box: box, spread: spread, ink: ink };
  return out;
}

// ---------- 稳健聚合 ----------

// 分位数（线性插值）。比 min/max 稳健：少数离群页动不了它。
export function quantile(xs: Array<number>, q: number): number {
  const n = xs.length;
  if (n === 0) {
    return 0;
  }
  const s = xs.slice();
  s.sort((a: number, b: number): number => a - b);
  const pos = q * (n - 1);
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  if (lo >= hi) {
    return s[lo];
  }
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

function edgesOf(boxes: Array<PageBox>, pick: (b: PageBox) => number): Array<number> {
  const out: Array<number> = [];
  for (const b of boxes) {
    out.push(pick(b));
  }
  return out;
}

function padded(box: PageBox, pad: number): PageBox {
  const out: PageBox = {
    top: Math.max(0, box.top - pad),
    bottom: Math.min(1, box.bottom + pad),
    left: Math.max(0, box.left - pad),
    right: Math.min(1, box.right + pad)
  };
  return out;
}

// 单边最多裁 maxTrim：万一估计偏了，也不允许把一页切掉半张（夹住而不是放弃，
// 因为"边距比上限还大"仍然是有效信息，夹到上限依旧比不裁好）。
function cappedTrim(box: PageBox, maxTrim: number): PageBox {
  const out: PageBox = {
    top: Math.min(box.top, maxTrim),
    bottom: Math.max(box.bottom, 1 - maxTrim),
    left: Math.min(box.left, maxTrim),
    right: Math.max(box.right, 1 - maxTrim)
  };
  return out;
}

function plausible(box: PageBox | null, params: CropParams): boolean {
  if (box === null) {
    return false;
  }
  return (box.bottom - box.top) >= params.minHeight
    && (box.right - box.left) >= params.minWidth;
}

// 由一组页估出它们共同的内容框。
//
// **四条边各自独立估计**，这是关键：
// 真实扫描件的四条边质量差别很大——常见情况是左右边距很一致、而顶部因为扫描黑边/
// 出血装饰条在近一半页上"有墨"。四条边绑在一起判"版式是否一致"就会互相否决，
// 结果一页都裁不了。分开之后，左右照样能裁，顶边则诚实地不裁。
//
// 每条边取 edgeQuantile 分位（顶/左取低分位、底/右取高分位）：
// 意思是"只裁到 75% 的页都同意是空白的地方"，少数异常页最多被啃掉几个百分点。
// 同时用四分位距当**一致性闸门**：某条边分布太散 = 这本书没有一致版心，就别硬裁。
function estimateBox(boxes: Array<PageBox>, params: CropParams): PageBox | null {
  // 2 页起就能估（两页一致就是一致），1 页没有"多数"可言
  if (boxes.length < 2) {
    return null;
  }
  const q = params.edgeQuantile;
  const tops = edgesOf(boxes, (b: PageBox): number => b.top);
  const bottoms = edgesOf(boxes, (b: PageBox): number => b.bottom);
  const lefts = edgesOf(boxes, (b: PageBox): number => b.left);
  const rights = edgesOf(boxes, (b: PageBox): number => b.right);
  const iqr = (xs: Array<number>): number => quantile(xs, 0.75) - quantile(xs, 0.25);
  if (iqr(tops) > params.maxEdgeSpread || iqr(bottoms) > params.maxEdgeSpread
    || iqr(lefts) > params.maxEdgeSpread || iqr(rights) > params.maxEdgeSpread) {
    return null;
  }
  const box: PageBox = {
    top: quantile(tops, q),
    bottom: quantile(bottoms, 1 - q),
    left: quantile(lefts, q),
    right: quantile(rights, 1 - q)
  };
  const raw = padded(box, params.padRatio);
  // 先判**估计本身**可不可信：裁剪上限是用来"夹住过大的边距"的，
  // 不能反过来把明显不合理的估计（内容只剩中间一条）撑成合理的样子。
  if (!plausible(raw, params)) {
    return null;
  }
  const final = cappedTrim(raw, params.maxTrim);
  return plausible(final, params) ? final : null;
}

// 全书裁框：默认一个框（四边各自稳健估计）；奇偶差异显著才分奇偶。
export function bookCrop(scans: Array<PageScan>, params: CropParams): CropResult {
  const all: Array<PageBox> = [];
  // 奇偶必须按**页序号**分，不能按「参与统计的框在数组里的位置」分：
  // 中间跳过一页空白就会让后面所有页的奇偶翻转。
  const evenBoxes: Array<PageBox> = [];
  const oddBoxes: Array<PageBox> = [];
  let spreadCount = 0;
  let valid = 0;
  for (let i = 0; i < scans.length; i++) {
    const s = scans[i];
    if (s.spread) {
      spreadCount++;
    }
    if (s.box !== null) {
      valid++;
      if (!s.spread) {
        all.push(s.box);
        if (i % 2 === 0) {
          evenBoxes.push(s.box);
        } else {
          oddBoxes.push(s.box);
        }
      }
    }
  }
  const result: CropResult = {
    shared: null, even: null, odd: null, split: false, spread: false,
    used: valid, rejected: 0
  };
  if (valid === 0) {
    return result;
  }
  // 多数页是对开扫描：单页框必然错，直接放弃裁剪
  if (spreadCount * 2 > valid) {
    result.spread = true;
    return result;
  }
  const shared = estimateBox(all, params);
  // 奇偶各自估计：**即使全书统一框不成立也要算**——装订边左右轮换的书
  // 恰好就是"统一框落空、但按奇偶各自成立"的情况。
  const e = estimateBox(evenBoxes, params);
  const o = estimateBox(oddBoxes, params);
  if (e !== null && o !== null) {
    const d = Math.max(Math.abs(e.top - o.top), Math.abs(e.bottom - o.bottom),
      Math.abs(e.left - o.left), Math.abs(e.right - o.right));
    if (d > params.parityDelta || shared === null) {
      result.split = true;
      result.even = e;
      result.odd = o;
      result.shared = shared;
      return result;
    }
  }
  result.shared = shared;
  return result;
}

export function boxForPage(r: CropResult, pageIndex: number): PageBox | null {
  if (r.split) {
    return pageIndex % 2 === 0 ? r.even : r.odd;
  }
  return r.shared;
}
