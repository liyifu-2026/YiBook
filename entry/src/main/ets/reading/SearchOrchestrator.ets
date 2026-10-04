import { rrfFuse, mmrSelect } from './RankFusion';
import { SourceBlock } from './PromptAssembler';

// 检索编排（问答管线设计·机制4-8）：双路排名 → RRF 融合 → MMR 去冗余
// → 组装 L4 引用块（id 为 1 起始的引用编号）。

export interface IndexedChunk {
  id: number;
  sourceLine: string;
  text: string;
  vec: Array<number>;
  pageIndex: number;
  charStart: number;
  charEnd: number;
}

export interface SelectedBlocks {
  blocks: Array<SourceBlock>;
}

const DEFAULT_TOP_K = 6;

// 铁律2 的执行：默认只检索已读范围（高水位线）；全书模式放开
export function filterRead(chunks: Array<IndexedChunk>, highWaterPage: number,
  wholeBook: boolean): Array<IndexedChunk> {
  if (wholeBook) {
    return chunks;
  }
  const out: Array<IndexedChunk> = [];
  for (const c of chunks) {
    if (c.pageIndex <= highWaterPage) {
      out.push(c);
    }
  }
  return out;
}

export function selectBlocks(queryVec: Array<number>, lexicalRanking: Array<number>,
  vectorRanking: Array<number>, chunks: Array<IndexedChunk>, lambda: number,
  maxTotalChars: number): SelectedBlocks {
  const fused = rrfFuse([lexicalRanking, vectorRanking], 60);
  const present: Array<IndexedChunk> = [];
  for (const id of fused) {
    for (const c of chunks) {
      if (c.id === id) {
        present.push(c);
        break;
      }
    }
  }
  let picked: Array<number> = [];
  if (queryVec.length === 0) {
    // 无向量路（BYOK 未配 embedding）：按融合序直取，不跑 MMR
    for (let i = 0; i < present.length && picked.length < DEFAULT_TOP_K; i++) {
      picked.push(i);
    }
  } else {
    const vecs: Array<Array<number>> = [];
    for (const c of present) {
      vecs.push(c.vec);
    }
    picked = mmrSelect(queryVec, vecs, lambda, DEFAULT_TOP_K);
  }
  const blocks: Array<SourceBlock> = [];
  let total = 0;
  for (const idx of picked) {
    const c = present[idx];
    if (total + c.text.length > maxTotalChars) {
      break;
    }
    const sb: SourceBlock = { id: blocks.length + 1, sourceLine: c.sourceLine, text: c.text };
    blocks.push(sb);
    total += c.text.length;
  }
  const out: SelectedBlocks = { blocks: blocks };
  return out;
}
