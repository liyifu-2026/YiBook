// 液态气泡模型（铁律4：永不自动展开，状态只进不退）。
// 生命周期：Thinking（思考中，液态彩流动）→ Done（完成，凝驻）→ Settled（收敛为常驻小点）。

export enum BubblePhase {
  Thinking = 0,
  Done = 1,
  Settled = 2
}

export interface QuestionBubble {
  id: number;
  pageIndex: number;
  anchorY: number; // 页内锚点Y（采样栅格坐标）
  phase: BubblePhase;
}

export function bubbleOnQuestion(id: number, pageIndex: number, anchorY: number): QuestionBubble {
  const b: QuestionBubble = { id: id, pageIndex: pageIndex, anchorY: anchorY, phase: BubblePhase.Thinking };
  return b;
}

export function markAnswerReady(b: QuestionBubble): QuestionBubble {
  if (b.phase !== BubblePhase.Thinking) {
    return b;
  }
  const out: QuestionBubble = { id: b.id, pageIndex: b.pageIndex, anchorY: b.anchorY, phase: BubblePhase.Done };
  return out;
}

export function markSettled(b: QuestionBubble): QuestionBubble {
  if (b.phase !== BubblePhase.Done) {
    return b;
  }
  const out: QuestionBubble = { id: b.id, pageIndex: b.pageIndex, anchorY: b.anchorY, phase: BubblePhase.Settled };
  return out;
}

// 锚点在长卷中的滚动坐标：页顶 + 页内比例 × 槽位高
export function anchorScrollY(pageTop: number, slotHeight: number, gridRows: number,
  anchorY: number): number {
  if (gridRows <= 0) {
    return pageTop;
  }
  return pageTop + (anchorY / gridRows) * slotHeight;
}

// 投影到视口；滚出视野返回 -1（调用方把气泡收成图钉）
export function projectToViewport(anchorScroll: number, scrollY: number, viewportHeight: number): number {
  const y = anchorScroll - scrollY;
  if (y < 0 || y > viewportHeight) {
    return -1;
  }
  return y;
}

// 同屏至多 maxVisible 枚，旧的折叠为 +N（设计定稿：超出折叠为「+N」）
export function foldBubbles(bubbles: Array<QuestionBubble>, maxVisible: number): FoldedBubbles {
  const extra = bubbles.length > maxVisible ? bubbles.length - maxVisible : 0;
  const shown: Array<QuestionBubble> = [];
  for (let i = extra; i < bubbles.length; i++) {
    shown.push(bubbles[i]);
  }
  const out: FoldedBubbles = { shown: shown, extraCount: extra };
  return out;
}

export interface FoldedBubbles {
  shown: Array<QuestionBubble>;
  extraCount: number;
}

// 跨会话恢复：从本书的问答记录重建「凝驻小点」（铁律3——历史提问回到原位）。
// id 从 idOffset 递增，避开会话内新提问的 id 空间。
export function bubblesFromQa(records: Array<QaAnchor>, inkKey: string, idOffset: number): Array<QuestionBubble> {
  const out: Array<QuestionBubble> = [];
  let id = idOffset;
  for (const rec of records) {
    if (rec.bookKey !== inkKey) {
      continue;
    }
    const b: QuestionBubble = {
      id: id,
      pageIndex: rec.pageIndex,
      anchorY: rec.anchorY,
      phase: BubblePhase.Settled
    };
    out.push(b);
    id++;
  }
  return out;
}

export interface QaAnchor {
  bookKey: string;
  pageIndex: number;
  anchorY: number;
}
