// 建书编排的纯函数零件：内容哈希（防重复 embedding 计费）与批量切分。

export function textHash(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h * 33) ^ s.charCodeAt(i)) & 0xFFFFFFFF;
  }
  const hex = (h >>> 0).toString(16);
  const padded = '00000000'.substring(0, 8 - hex.length) + hex;
  return `${padded}_${s.length}`;
}

export function batchTexts(texts: Array<string>, maxBatch: number): Array<Array<string>> {
  const size = maxBatch < 1 ? 1 : maxBatch;
  const batches: Array<Array<string>> = [];
  let current: Array<string> = [];
  for (const t of texts) {
    current.push(t);
    if (current.length >= size) {
      batches.push(current);
      current = [];
    }
  }
  if (current.length > 0) {
    batches.push(current);
  }
  return batches;
}

// embedding 缓存查找：命中返回该块向量，未命中或维度不符返回 null
export function cacheLookup(hash: string, hashes: Array<string>, data: Float32Array,
  dims: number): Array<number> | null {
  if (dims <= 0) {
    return null;
  }
  const at = hashes.indexOf(hash);
  if (at < 0 || (at + 1) * dims > data.length) {
    return null;
  }
  const out: Array<number> = [];
  for (let d = 0; d < dims; d++) {
    out.push(data[at * dims + d]);
  }
  return out;
}

export interface MissingPlan {
  missingIdx: Array<number>;            // 需要新 embedding 的块下标
  vecs: Array<Array<number> | null>;    // 每块向量（缓存命中填充，未命中 null）
}

export interface VectorAssembly {
  data: Float32Array;
  embeddedCount: number;
}

// 纯函数：把「缓存命中 + 新 embedding」的向量装配为落盘/入索引的连续数组。
// 维度不符的向量（如换模型残留）跳过不计。
export function assembleVectors(vecs: Array<Array<number> | null>, dims: number): VectorAssembly {
  const data = new Float32Array(vecs.length * dims);
  let embeddedCount = 0;
  for (let i = 0; i < vecs.length; i++) {
    const v = vecs[i];
    if (v !== null && v !== undefined && v.length === dims) {
      data.set(v, i * dims);
      embeddedCount++;
    }
  }
  const out: VectorAssembly = { data: data, embeddedCount: embeddedCount };
  return out;
}

// 纯函数：给定块哈希与缓存，产出缺算计划（BookIndexer 编排的可测核心）
export function planMissing(chunkHashes: Array<string>, cacheHashes: Array<string>,
  data: Float32Array, dims: number): MissingPlan {
  const missingIdx: Array<number> = [];
  const vecs: Array<Array<number> | null> = [];
  for (let i = 0; i < chunkHashes.length; i++) {
    const v = cacheLookup(chunkHashes[i], cacheHashes, data, dims);
    vecs.push(v);
    if (v === null) {
      missingIdx.push(i);
    }
  }
  const plan: MissingPlan = { missingIdx: missingIdx, vecs: vecs };
  return plan;
}
