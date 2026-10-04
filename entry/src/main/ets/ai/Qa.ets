// 问答记录（铁律3：条条可回跳）：全局 qa.json，书房按书归档、点击跳回原文页。

export interface QaRecord {
  bookKey: string;
  bookTitle: string;
  bookPath: string;
  pageIndex: number;   // 0-based
  anchorY: number;     // 圈选锚点（采样栅格 Y），旧记录缺失按 0 处理
  chapterTitle: string;
  question: string;
  answer: string;
  createdAt: number;
}

export interface QaGroup {
  chapterTitle: string;
  items: Array<QaRecord>;
}

// 书房详情页：问答按章归组，章按书中位置升序，组内按页升序
export function groupQaByChapter(qas: Array<QaRecord>): Array<QaGroup> {
  const groups: Array<QaGroup> = [];
  for (const rec of qas) {
    let target: QaGroup | undefined = undefined;
    for (const g of groups) {
      if (g.chapterTitle === rec.chapterTitle) {
        target = g;
        break;
      }
    }
    if (target === undefined) {
      const g: QaGroup = { chapterTitle: rec.chapterTitle, items: [] };
      groups.push(g);
      target = g;
    }
    target.items.push(rec);
  }
  const minPage = (g: QaGroup): number => {
    let m = Number.MAX_SAFE_INTEGER;
    for (const it of g.items) {
      if (it.pageIndex < m) {
        m = it.pageIndex;
      }
    }
    return m;
  };
  groups.sort((a, b) => minPage(a) - minPage(b));
  for (const g of groups) {
    g.items.sort((a, b) => a.pageIndex - b.pageIndex);
  }
  return groups;
}
