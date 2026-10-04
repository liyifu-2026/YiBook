// 词法索引：中文 bigram + 拉丁词的 BM25（决策 #16 的 v1 近似，
// 替代 FTS5 原生扩展；jieba 词级分词留给优化路径）。

export function isCjkChar(code: number): boolean {
  return (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF);
}

export function tokenize(text: string): Array<string> {
  const lower = text.toLowerCase();
  const tokens: Array<string> = [];
  let i = 0;
  while (i < lower.length) {
    const code = lower.charCodeAt(i);
    if (isCjkChar(code)) {
      let j = i;
      while (j < lower.length && isCjkChar(lower.charCodeAt(j))) {
        j++;
      }
      const run = lower.substring(i, j);
      if (run.length === 1) {
        tokens.push(run);
      } else {
        for (let b = 0; b + 2 <= run.length; b++) {
          tokens.push(run.substring(b, b + 2));
        }
      }
      i = j;
    } else if ((code >= 97 && code <= 122) || (code >= 48 && code <= 57)) {
      let j = i;
      while (j < lower.length) {
        const c2 = lower.charCodeAt(j);
        if ((c2 >= 97 && c2 <= 122) || (c2 >= 48 && c2 <= 57)) {
          j++;
        } else {
          break;
        }
      }
      tokens.push(lower.substring(i, j));
      i = j;
    } else {
      i++;
    }
  }
  return tokens;
}

const K1 = 1.5;
const B = 0.75;

export class LexicalIndex {
  private tfs: Map<number, Map<string, number>> = new Map();
  private docLens: Map<number, number> = new Map();
  private df: Map<string, number> = new Map();
  private totalLen: number = 0;

  add(id: number, text: string): void {
    const terms = tokenize(text);
    const tf = new Map<string, number>();
    for (const t of terms) {
      const cur = tf.get(t);
      tf.set(t, cur === undefined ? 1 : (cur as number) + 1);
    }
    for (const t of tf.keys()) {
      const cur = this.df.get(t);
      this.df.set(t, cur === undefined ? 1 : (cur as number) + 1);
    }
    this.tfs.set(id, tf);
    this.docLens.set(id, terms.length);
    this.totalLen += terms.length;
  }

  search(query: string, topK: number): Array<number> {
    const n = this.tfs.size;
    if (n === 0) {
      return [];
    }
    const avgLen = this.totalLen / n;
    const scores = new Map<number, number>();
    const qTerms = tokenize(query);
    for (const t of qTerms) {
      const df = this.df.get(t);
      if (df === undefined) {
        continue;
      }
      const idf = Math.log((n - (df as number) + 0.5) / ((df as number) + 0.5) + 1);
      for (const id of this.tfs.keys()) {
        const tf = (this.tfs.get(id) as Map<string, number>).get(t);
        if (tf === undefined) {
          continue;
        }
        const tfv = tf as number;
        const len = this.docLens.get(id) as number;
        const denom = tfv + K1 * (1 - B + B * len / avgLen);
        const gain = idf * tfv * (K1 + 1) / denom;
        const cur = scores.get(id);
        scores.set(id, cur === undefined ? gain : (cur as number) + gain);
      }
    }
    const ids: Array<number> = [];
    for (const id of scores.keys()) {
      ids.push(id);
    }
    ids.sort((a, b) => (scores.get(b) as number) - (scores.get(a) as number));
    return ids.slice(0, Math.min(topK, ids.length));
  }
}
