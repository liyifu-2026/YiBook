// 通用数组分批（纯函数）。
//
// 为什么放在 core 而不是 book：ai/EmbeddingClient 与 book/IndexerMath 都要用它，
// 若定义留在 book 就会形成 ai → book 的域级交叉引用。
//
// 本文件必须保持纯逻辑，禁止 import @ohos / @kit。

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
