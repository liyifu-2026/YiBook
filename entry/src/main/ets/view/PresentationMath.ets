// 视图层的纯呈现计算。
//
// 为什么自 view/ReaderView 与 view/LibraryView 抽出：这些分支逻辑（索引按钮文案、
// 封面形变、书架列数、详情统计行）原本埋在上千行的 ArkUI 组件里，没有任何测试覆盖。
// 抽成纯函数后可单测，视图只负责把状态传进来、把结果绑到属性上。
//
// 命名约定：本文件的函数名一律与视图里的私有包装方法区分开（不重名），
// 否则 `return cellWidthPct(...)` 这种写法看起来像无限递归，极易误读。
//
// 本文件必须保持纯逻辑，禁止 import @ohos / @kit 与 ArkUI。

// 索引按钮文案，优先级：版式分析中 > 建索引中 > 部分已索引 > 已索引 > 未索引
export function indexButtonLabel(analysisStatus: string, indexStatus: string,
  indexReady: boolean, indexCap: number, totalPages: number): string {
  if (analysisStatus !== '') {
    return analysisStatus;
  }
  if (indexStatus !== '') {
    return indexStatus;
  }
  if (indexReady && indexCap < totalPages) {
    return `索引 ${indexCap}/${totalPages}`;
  }
  if (indexReady) {
    return '已索引';
  }
  return '索引';
}

// 封面的按压/悬停形变：按下去落进自己的影子，悬停时从影子里浮起
export function coverCellScale(key: string, pressedKey: string, hoverKey: string): number {
  if (pressedKey === key) {
    return 0.97;
  }
  return hoverKey === key ? 1.03 : 1.0;
}

export function coverCellShift(key: string, pressedKey: string): number {
  return pressedKey === key ? 4 : 0;
}

// 书越少列越少：封面越大，画廊感越强；书多了回归密排封面墙
export function shelfColumns(bookCount: number): number {
  if (bookCount <= 3) {
    return 3;
  }
  if (bookCount <= 8) {
    return 4;
  }
  return 5;
}

export function coverCellWidthPct(columnCount: number): string {
  if (columnCount === 3) {
    return '29%';
  }
  if (columnCount === 4) {
    return '21.5%';
  }
  return '17%';
}

// 详情态统计行：问答数 · 已读页（未读过不显示） · 是否有草稿
export function bookDetailStats(qaCount: number, highWater: number, hasDraft: boolean): string {
  let s = `问答 ${qaCount}`;
  if (highWater >= 0) {
    s += ` · 已读 P${highWater + 1}`;
  }
  if (hasDraft) {
    s += ' · 有草稿';
  }
  return s;
}
