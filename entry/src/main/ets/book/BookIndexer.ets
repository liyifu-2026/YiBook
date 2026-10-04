import { chunkText } from '../search/Chunker';
import { textHash, planMissing, assembleVectors } from './IndexerMath';
import { OcrTexts } from './OcrTexts';
import { LexicalIndex } from '../search/LexicalIndex';
import { VectorIndex } from '../search/VectorIndex';
import { IndexedChunk } from '../search/SearchOrchestrator';
import { PageImageSource, PageTextSource, PageVision, TextEmbedder, VectorCache } from '../core/Ports';

// 建书编排器（AGENTS.md 管线：文本提取→切分→哈希→缓存命中→增量 embedding→双索引）。
// 纯 T0：只索引有文字层的页；扫描页留给 T1/T3。
//
// 本类只依赖 core/Ports 的抽象（PageImageSource / PageTextSource / TextEmbedder /
// PageVision / VectorCache），不 import ai 域与 pdf 域的任何具体实现：
//   - 消除 book ↔ ai、book ↔ pdf 两处域级交叉引用；
//   - 让编排逻辑可脱离 @kit 在本地单测中验证
//     （实测本地单测运行时无法执行 @kit 文件 IO 与网络）。
// 具体实现由调用方（view/ReaderView）组装后注入。

const CHUNK_TARGET = 400;
const CHUNK_MAX = 600;

export interface BuildResult {
  chunks: Array<IndexedChunk>;
  lexical: LexicalIndex;
  vector: VectorIndex;
  embeddedCount: number;
  configError: boolean; // embedding 维度与配置不符（调用方应提示用户检查模型）
}

export class BookIndexer {
  // T3：全书 OCR——只转录缺失页，文字层页直接标记为已覆盖
  async ensureOcr(source: PageImageSource, ocrTexts: OcrTexts, vision: PageVision,
    pageCount: number, maxPages: number,
    onProgress: (done: number, total: number) => void): Promise<number> {
    if (!vision.available()) {
      return 0;
    }
    const cap = Math.min(pageCount, maxPages);
    const missing: Array<number> = [];
    const want = ocrTexts.missingPages(pageCount, maxPages);
    for (const i of want) {
      const native = source.pageText(i);
      if (native.trim() !== '') {
        ocrTexts.set(i, native); // 文字层页零成本覆盖
      } else {
        missing.push(i);
      }
    }
    const total = missing.length;
    if (total === 0) {
      return 0;
    }
    let done = 0;
    for (const i of missing) {
      try {
        const b64 = await source.pageJpegBase64(i);
        if (b64 !== '') {
          const text = await vision.extractText(b64, 'image/jpeg');
          // 只缓存非空转录：网络失败留在缺失集，下次索引可重试（空文本不哑雷）
          if (text.trim() !== '') {
            ocrTexts.set(i, text);
          }
        }
      } catch (err) {
        // 单页渲染/网络抛错不拖垮整批：留在缺失集，下次重试
      }
      done++;
      onProgress(done, total);
    }
    return total;
  }

  async build(source: PageTextSource, pageCount: number, maxPages: number,
    embed: TextEmbedder | null, cache: VectorCache,
    onProgress: (done: number, total: number) => void,
    ocrTexts: OcrTexts | null): Promise<BuildResult> {
    const total = Math.min(pageCount, maxPages);
    const chunkIds: Array<number> = [];
    const chunkTexts: Array<string> = [];
    const chunkHashes: Array<string> = [];
    const chunkLines: Array<string> = [];
    const chunkPages: Array<number> = [];
    const chunkStarts: Array<number> = [];
    const chunkEnds: Array<number> = [];
    const lexical = new LexicalIndex();
    let nextId = 1;
    for (let i = 0; i < total; i++) {
      let text = source.pageText(i);
      if (text.trim() === '' && ocrTexts !== null && ocrTexts.has(i)) {
        text = ocrTexts.get(i);
      }
      if (text.trim() === '') {
        continue;
      }
      const chunks = chunkText(text, CHUNK_TARGET, CHUNK_MAX);
      for (const c of chunks) {
        chunkIds.push(nextId);
        chunkTexts.push(c.text);
        chunkHashes.push(textHash(c.text));
        chunkLines.push(`P${i + 1}`);
        chunkPages.push(i);
        chunkStarts.push(c.charStart);
        chunkEnds.push(c.charEnd);
        lexical.add(nextId, c.text);
        nextId++;
      }
      onProgress(i + 1, total);
      if ((i + 1) % 12 === 0) {
        // 60 页同步取文会卡 UI：分批让出主线程
        await new Promise<void>((resolve: () => void) => {
          setTimeout(resolve, 0);
        });
      }
    }
    const vector = new VectorIndex();
    const cached = cache.load();
    // 维度以缓存为准；无缓存时推迟到首个真实向量落地后再定——硬编码 1024 会让
    // 1536/2048 维模型整链失败且永不落缓存、重复计费
    let dims = cached !== null && cached.dims > 0 ? cached.dims : 0;
    let embeddedCount = 0;
    let dimError = false;
    const plan = planMissing(chunkHashes,
      cached !== null ? cached.hashes : [], cached !== null ? cached.data : new Float32Array(0), dims);
    const missingIdx = plan.missingIdx;
    if (embed !== null && embed.available() && missingIdx.length > 0) {
      const missingTexts: Array<string> = [];
      for (const i of missingIdx) {
        missingTexts.push(chunkTexts[i]);
      }
      const vecs = await embed.embed(missingTexts);
      if (vecs.length === missingTexts.length && vecs.length > 0) {
        if (dims === 0) {
          dims = vecs[0].length;
        }
        for (let k = 0; k < missingIdx.length; k++) {
          if (vecs[k].length === dims) {
            plan.vecs[missingIdx[k]] = vecs[k];
          } else {
            dimError = true;
          }
        }
      }
    }
    if (dims === 0) {
      // 无向量可装配（embedding 不可用）：占位维度，检索退化为词法单路
      dims = 1;
    }
    // 单一事实源：plan.vecs（缓存命中 + 新 embedding）一次性装配
    const asm = assembleVectors(plan.vecs, dims);
    embeddedCount = asm.embeddedCount;
    for (let i = 0; i < chunkTexts.length; i++) {
      const v = plan.vecs[i];
      if (v !== null && v !== undefined && v.length === dims) {
        vector.add(chunkIds[i], v);
      }
    }
    // 只有全部块都拿到合法向量时才落缓存（部分失败可重试）；维度不符视为配置错误不落缓存
    if (asm.embeddedCount === chunkTexts.length && chunkTexts.length > 0 && !dimError) {
      cache.save(chunkHashes, dims, asm.data);
    }
    const chunks: Array<IndexedChunk> = [];
    for (let i = 0; i < chunkTexts.length; i++) {
      const vec: Array<number> = [];
      for (let d = 0; d < dims; d++) {
        vec.push(asm.data[i * dims + d]);
      }
      const c: IndexedChunk = {
        id: chunkIds[i],
        sourceLine: chunkLines[i],
        text: chunkTexts[i],
        vec: vec,
        pageIndex: chunkPages[i],
        charStart: chunkStarts[i],
        charEnd: chunkEnds[i]
      };
      chunks.push(c);
    }
    const result: BuildResult = {
      chunks: chunks,
      lexical: lexical,
      vector: vector,
      embeddedCount: embeddedCount,
      configError: dimError
    };
    return result;
  }


}
