// 向量索引：内存线性扫（决策 #16——327页≈2000块毫秒级，sqlite-vec 留优化路径）。

export class VectorIndex {
  private vecs: Map<number, Array<number>> = new Map();

  add(id: number, vec: Array<number>): void {
    this.vecs.set(id, vec);
  }

  search(query: Array<number>, topK: number): Array<number> {
    const k = Math.min(topK, this.vecs.size);
    if (k <= 0) {
      return [];
    }
    const scored: Array<Scored> = [];
    for (const id of this.vecs.keys()) {
      const v = this.vecs.get(id) as Array<number>;
      let dot = 0;
      let nq = 0;
      let nv = 0;
      for (let i = 0; i < query.length; i++) {
        dot += query[i] * v[i];
        nq += query[i] * query[i];
        nv += v[i] * v[i];
      }
      const sim = (nq === 0 || nv === 0) ? 0 : dot / (Math.sqrt(nq) * Math.sqrt(nv));
      const s: Scored = { id: id, score: sim };
      scored.push(s);
    }
    scored.sort((a, b) => b.score - a.score);
    const out: Array<number> = [];
    for (let i = 0; i < k; i++) {
      out.push(scored[i].id);
    }
    return out;
  }
}

interface Scored {
  id: number;
  score: number;
}
