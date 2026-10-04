import { describe, it, expect } from '@ohos/hypium';
import { BookIndexer, BuildResult } from '../main/ets/book/BookIndexer';
import { OcrTexts } from '../main/ets/book/OcrTexts';
import { CacheData, PageImageSource, PageVision, TextEmbedder, VectorCache } from '../main/ets/core/Ports';

// BookIndexer 的行为网。
//
// 为什么全部用内存替身：已实测本地单测运行时无法执行 @kit 文件 IO 与网络
// （writeJsonFile 返回 false），因此端口必须注入纯内存实现。
// 这也正是 B 项把 BookIndexer 改为依赖 core/Ports 抽象的直接收益。
//
// 页数一律 < 12，避开 build() 里每 12 页一次的 setTimeout 让出主线程。

class FakePageSource implements PageImageSource {
  private pages: Array<string>;
  jpegCalls: Array<number> = [];

  constructor(pages: Array<string>) {
    this.pages = pages;
  }

  pageText(index: number): string {
    return (index >= 0 && index < this.pages.length) ? this.pages[index] : '';
  }

  async pageJpegBase64(index: number): Promise<string> {
    this.jpegCalls.push(index);
    return `JPEG-${index}`;
  }
}

class FakeEmbedder implements TextEmbedder {
  callCount: number = 0;
  lastBatchSize: number = -1;
  private on: boolean;
  private dims: number;

  constructor(on: boolean, dims: number) {
    this.on = on;
    this.dims = dims;
  }

  available(): boolean {
    return this.on;
  }

  async embed(texts: Array<string>): Promise<Array<Array<number>>> {
    this.callCount++;
    this.lastBatchSize = texts.length;
    const out: Array<Array<number>> = [];
    for (let i = 0; i < texts.length; i++) {
      const v: Array<number> = [];
      for (let d = 0; d < this.dims; d++) {
        v.push(texts[i].length + d);
      }
      out.push(v);
    }
    return out;
  }
}

class FakeVision implements PageVision {
  calls: number = 0;
  private on: boolean;
  private texts: Map<number, string>;
  private throwOn: Array<number>;

  constructor(on: boolean, texts: Map<number, string>, throwOn: Array<number>) {
    this.on = on;
    this.texts = texts;
    this.throwOn = throwOn;
  }

  available(): boolean {
    return this.on;
  }

  async extractText(imageBase64: string, mime: string): Promise<string> {
    this.calls++;
    const page = Number(imageBase64.substring('JPEG-'.length));
    if (this.throwOn.indexOf(page) >= 0) {
      throw new Error('network down');
    }
    const v = this.texts.get(page);
    return v === undefined ? '' : v;
  }
}

class MemoryCache implements VectorCache {
  data: CacheData | null = null;
  saves: number = 0;
  lastDims: number = -1;

  load(): CacheData | null {
    return this.data;
  }

  save(hashes: Array<string>, dims: number, data: Float32Array): void {
    this.saves++;
    this.lastDims = dims;
    this.data = { hashes: hashes, dims: dims, data: data };
  }
}

function noop(_done: number, _total: number): void {
}

export default function bookIndexerTest() {
  describe('bookIndexer', () => {

    it('skips pages without text and keeps 1-based source line labels', 0, async () => {
      const src = new FakePageSource(['', 'hello world', '   ']);
      const cache = new MemoryCache();
      const r: BuildResult = await new BookIndexer()
        .build(src, 3, 10, null, cache, noop, null);
      expect(r.chunks.length).assertEqual(1);
      expect(r.chunks[0].pageIndex).assertEqual(1);
      expect(r.chunks[0].sourceLine).assertEqual('P2');
      expect(r.chunks[0].text).assertEqual('hello world');
    });

    it('falls back to OCR text when the page has no text layer', 0, async () => {
      const src = new FakePageSource(['', '']);
      const ocr = new OcrTexts();
      ocr.set(1, 'ocr transcribed text');
      const cache = new MemoryCache();
      const r: BuildResult = await new BookIndexer()
        .build(src, 2, 10, null, cache, noop, ocr);
      expect(r.chunks.length).assertEqual(1);
      expect(r.chunks[0].pageIndex).assertEqual(1);
      expect(r.chunks[0].text).assertEqual('ocr transcribed text');
    });

    it('attaches vectors and persists the cache when every chunk is embedded', 0, async () => {
      const src = new FakePageSource(['alpha', 'beta']);
      const cache = new MemoryCache();
      const embed = new FakeEmbedder(true, 3);
      const r: BuildResult = await new BookIndexer()
        .build(src, 2, 10, embed, cache, noop, null);
      expect(r.chunks.length).assertEqual(2);
      expect(r.embeddedCount).assertEqual(2);
      expect(r.configError).assertFalse();
      expect(r.chunks[0].vec.length).assertEqual(3);
      expect(cache.saves).assertEqual(1);
      expect(cache.lastDims).assertEqual(3);
    });

    it('reuses the cache on a second build and never re-embeds (zero repeat billing)', 0, async () => {
      const src = new FakePageSource(['alpha', 'beta']);
      const cache = new MemoryCache();
      const embed = new FakeEmbedder(true, 3);
      const indexer = new BookIndexer();
      await indexer.build(src, 2, 10, embed, cache, noop, null);
      const callsAfterFirst: number = embed.callCount;
      expect(callsAfterFirst).assertEqual(1);
      const again: BuildResult = await indexer.build(src, 2, 10, embed, cache, noop, null);
      // 关键不变量：命中缓存后不再调用 embedding，计费不重复
      expect(embed.callCount).assertEqual(callsAfterFirst);
      expect(again.embeddedCount).assertEqual(2);
      expect(again.chunks[0].vec.length).assertEqual(3);
    });

    it('degrades to lexical-only when embedding is unavailable and does not cache', 0, async () => {
      const src = new FakePageSource(['alpha', 'beta']);
      const cache = new MemoryCache();
      const embed = new FakeEmbedder(false, 3);
      const r: BuildResult = await new BookIndexer()
        .build(src, 2, 10, embed, cache, noop, null);
      expect(r.chunks.length).assertEqual(2);
      expect(r.embeddedCount).assertEqual(0);
      expect(embed.callCount).assertEqual(0);
      expect(cache.saves).assertEqual(0);
    });

    it('reports a config error and skips caching when vector dims disagree with the cache', 0, async () => {
      const src = new FakePageSource(['alpha']);
      const cache = new MemoryCache();
      // 预置维度 3 的缓存，但哈希不匹配；embedder 却返回 2 维 → 换模型残留场景
      cache.data = { hashes: ['stale-hash'], dims: 3, data: new Float32Array([1, 2, 3]) };
      const embed = new FakeEmbedder(true, 2);
      const r: BuildResult = await new BookIndexer()
        .build(src, 1, 10, embed, cache, noop, null);
      expect(r.configError).assertTrue();
      expect(r.embeddedCount).assertEqual(0);
      expect(cache.saves).assertEqual(0);
    });

    it('reports page progress up to the analysed page count', 0, async () => {
      const src = new FakePageSource(['a', 'b', 'c']);
      const cache = new MemoryCache();
      const seen: Array<string> = [];
      await new BookIndexer().build(src, 3, 10, null, cache,
        (done: number, total: number): void => {
          seen.push(`${done}/${total}`);
        }, null);
      expect(seen.length).assertEqual(3);
      expect(seen[0]).assertEqual('1/3');
      expect(seen[2]).assertEqual('3/3');
    });

    it('caps the analysed pages at maxPages', 0, async () => {
      const src = new FakePageSource(['a', 'b', 'c', 'd']);
      const cache = new MemoryCache();
      const r: BuildResult = await new BookIndexer()
        .build(src, 4, 2, null, cache, noop, null);
      expect(r.chunks.length).assertEqual(2);
    });

    it('covers text-layer pages for free and only OCRs the truly missing ones', 0, async () => {
      const src = new FakePageSource(['native text', '']);
      const ocr = new OcrTexts();
      const vision = new FakeVision(true, new Map(), []);
      const done = await new BookIndexer().ensureOcr(src, ocr, vision, 2, 10, noop);
      expect(done).assertEqual(1);
      expect(ocr.get(0)).assertEqual('native text');
      // 只对缺文字层的第 1 页取图，文字层页零成本
      expect(src.jpegCalls.length).assertEqual(1);
      expect(src.jpegCalls[0]).assertEqual(1);
      expect(vision.calls).assertEqual(1);
    });

    it('does not cache an empty transcription so the page stays retryable', 0, async () => {
      const src = new FakePageSource(['']);
      const ocr = new OcrTexts();
      const vision = new FakeVision(true, new Map(), []);
      const done = await new BookIndexer().ensureOcr(src, ocr, vision, 1, 10, noop);
      expect(done).assertEqual(1);
      expect(ocr.has(0)).assertFalse();
    });

    it('keeps going when one page throws, so a bad page cannot kill the batch', 0, async () => {
      const src = new FakePageSource(['', '', '']);
      const ocr = new OcrTexts();
      const texts = new Map<number, string>();
      texts.set(2, 'third page text');
      const vision = new FakeVision(true, texts, [1]);
      const done = await new BookIndexer().ensureOcr(src, ocr, vision, 3, 10, noop);
      expect(done).assertEqual(3);
      expect(ocr.has(1)).assertFalse();
      expect(ocr.get(2)).assertEqual('third page text');
    });

    it('does nothing when vision is unavailable', 0, async () => {
      const src = new FakePageSource(['', '']);
      const ocr = new OcrTexts();
      const vision = new FakeVision(false, new Map(), []);
      const done = await new BookIndexer().ensureOcr(src, ocr, vision, 2, 10, noop);
      expect(done).assertEqual(0);
      expect(src.jpegCalls.length).assertEqual(0);
      expect(vision.calls).assertEqual(0);
    });

    it('never OCRs pages beyond maxPages', 0, async () => {
      const src = new FakePageSource(['', '', '']);
      const ocr = new OcrTexts();
      const vision = new FakeVision(true, new Map(), []);
      const done = await new BookIndexer().ensureOcr(src, ocr, vision, 3, 2, noop);
      expect(done).assertEqual(2);
      expect(src.jpegCalls.length).assertEqual(2);
    });
  });
}
