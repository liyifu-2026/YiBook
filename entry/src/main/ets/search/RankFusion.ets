// 检索融合（问答管线设计·机制6/7）：RRF 合并 BM25 与向量两路排名，
// MMR 在送 prompt 前去冗余。参数 k=60、λ=0.6 见管线文档。

export function rrfFuse(rankings: Array<Array<number>>, k: number): Array<number> {
  const scores = new Map<number, number>();
  const firstSeen: Array<number> = [];
  for (const ranking of rankings) {
    for (let r = 0; r < ranking.length; r++) {
      const id = ranking[r];
      const gain = 1 / (k + r + 1);
      if (!scores.has(id)) {
        scores.set(id, gain);
        firstSeen.push(id);
      } else {
        scores.set(id, (scores.get(id) as number) + gain);
      }
    }
  }
  const ids = firstSeen.slice();
  ids.sort((a, b) => (scores.get(b) as number) - (scores.get(a) as number));
  return ids;
}

function cosine(a: Array<number>, b: Array<number>): number {
  // 维度不一致（如查询向量与过期索引的块向量）不可比：按相似度 0 处理而非产生 NaN
  if (a.length !== b.length || a.length === 0) {
    return 0;
  }
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na === 0 || nb === 0) {
    return 0;
  }
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

export function mmrSelect(query: Array<number>, candidates: Array<Array<number>>,
  lambda: number, k: number): Array<number> {
  const selected: Array<number> = [];
  const remaining: Array<number> = [];
  for (let i = 0; i < candidates.length; i++) {
    remaining.push(i);
  }
  while (selected.length < k && remaining.length > 0) {
    let bestIdx = -1;
    let bestScore = -Infinity;
    for (const idx of remaining) {
      const rel = cosine(query, candidates[idx]);
      let maxSim = -Infinity;
      for (const sel of selected) {
        const sim = cosine(candidates[sel], candidates[idx]);
        if (sim > maxSim) {
          maxSim = sim;
        }
      }
      const penalty = selected.length === 0 ? 0 : (1 - lambda) * maxSim;
      const score = lambda * rel - penalty;
      if (score > bestScore) {
        bestScore = score;
        bestIdx = idx;
      }
    }
    // 全部候选不可比（维度不符/零向量）时提前收束，避免 -1 混入选中集
    if (bestIdx < 0) {
      break;
    }
    selected.push(bestIdx);
    const pos = remaining.indexOf(bestIdx);
    remaining.splice(pos, 1);
  }
  return selected;
}
