import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, it, expect } from '@ohos/hypium';
import { PdfPageSource } from '../../../main/ets/pdf/PdfPageSource';
import { chaptersFromOutline } from '../../../main/ets/book/ChapterModel';
import { Chapter, OutlineMarker } from '../../../main/ets/core/DocModel';

// D 项：用真正带文字层 + 真书签的原生 PDF 验证「文本锚定」与「章节提取」。
//
// 这一层只有真机能验：文字层与书签都由 @kit.PDFKit 提供，本地单测运行时
// 既跑不了 @kit，也没有 PDF 解析能力。
//
// 素材：entry/src/main/resources/rawfile/sample_native.pdf
//       自《Go语言学习笔记》正文节选 20 页（第 0..19 页），保留原书书签并重映射。
// ground truth 由 pypdf 离线核对：
//   页数 20；10 条书签解析为 8 个去重页 [1,3,4,5,6,9,16,18]（第 16 页有 3 条，验同页去重）；
//   密度 8*2=16 <= 20，不触发垃圾书签防御 → 期望 9 章（卷首 0..0 + 8 章），连续覆盖 0..19。

const TAG = 'NativePdfTest';
const RAW_NAME = 'sample_native.pdf';

async function materialize(): Promise<string> {
  const app = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const dest = app.filesDir + '/' + RAW_NAME;

  // 策略 A：应用级上下文的资源管理器
  let bytes: Uint8Array | null = null;
  let via = '';
  try {
    bytes = await app.resourceManager.getRawFileContent(RAW_NAME);
    via = 'appContext.resourceManager';
  } catch (err) {
    hilog.warn(0x0000, TAG, 'strategy A failed: %{public}s', JSON.stringify(err));
  }
  // 策略 B：显式取 entry 模块上下文
  if (bytes === null) {
    try {
      const modCtx = app.createModuleContext('entry');
      bytes = await modCtx.resourceManager.getRawFileContent(RAW_NAME);
      via = 'createModuleContext(entry)';
    } catch (err) {
      hilog.warn(0x0000, TAG, 'strategy B failed: %{public}s', JSON.stringify(err));
    }
  }
  if (bytes === null) {
    throw new Error('cannot read rawfile ' + RAW_NAME);
  }
  hilog.info(0x0000, TAG, 'rawfile read via %{public}s, %{public}d bytes', via, bytes.length);

  if (fs.accessSync(dest)) {
    fs.unlinkSync(dest);
  }
  const fd = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(fd.fd, bytes.buffer as ArrayBuffer);
  fs.closeSync(fd);
  return dest;
}

export default function nativePdfTest() {
  describe('nativePdf', () => {

    it('reads a real text layer from a native PDF', 0, async () => {
      const path = await materialize();
      const src = new PdfPageSource();
      expect(src.open(path)).assertTrue();
      const n = src.pageCount();
      hilog.info(0x0000, TAG, 'pageCount=%{public}d', n);
      expect(n).assertEqual(20);

      // 文本锚定的地基：文字层必须真的读得出来
      let nonEmpty = 0;
      let totalChars = 0;
      for (let i = 0; i < n; i++) {
        const t = src.pageText(i);
        totalChars += t.length;
        if (t.trim() !== '') {
          nonEmpty++;
        }
      }
      hilog.info(0x0000, TAG, 'pages with text=%{public}d, total chars=%{public}d', nonEmpty, totalChars);
      const sample = src.pageText(5);
      hilog.info(0x0000, TAG, 'page5 sample: %{public}s', sample.substring(0, 80));
      expect(sample.trim().length > 50).assertTrue();
      // 节选是正文，不应出现「几乎全是空页」的扫描件特征
      expect(nonEmpty >= n - 3).assertTrue();
      src.close();
    });

    it('extracts real bookmarks and keeps their page numbers in range', 0, async () => {
      const path = await materialize();
      const src = new PdfPageSource();
      expect(src.open(path)).assertTrue();
      const n = src.pageCount();
      const markers: Array<OutlineMarker> = src.outlineMarkers();
      hilog.info(0x0000, TAG, 'markers=%{public}d', markers.length);
      for (const m of markers) {
        hilog.info(0x0000, TAG, '  marker p=%{public}d title=%{public}s', m.page, m.title);
      }
      expect(markers.length).assertEqual(10);
      for (const m of markers) {
        expect(m.page >= 0).assertTrue();
        expect(m.page < n).assertTrue();
      }
      const pages: Array<number> = [];
      for (const m of markers) {
        if (pages.indexOf(m.page) < 0) {
          pages.push(m.page);
        }
      }
      pages.sort((a, b) => a - b);
      const expected: Array<number> = [1, 3, 4, 5, 6, 9, 16, 18];
      expect(pages.length).assertEqual(expected.length);
      for (let i = 0; i < expected.length; i++) {
        expect(pages[i]).assertEqual(expected[i]);
      }
      src.close();
    });

    it('splits chapters from the real outline into contiguous coverage', 0, async () => {
      const path = await materialize();
      const src = new PdfPageSource();
      expect(src.open(path)).assertTrue();
      const n = src.pageCount();
      const markers = src.outlineMarkers();
      const chapters: Array<Chapter> = chaptersFromOutline(markers, n);
      hilog.info(0x0000, TAG, 'chapters=%{public}d', chapters.length);
      for (const c of chapters) {
        hilog.info(0x0000, TAG, '  chapter %{public}d..%{public}d title=%{public}s manual=%{public}s',
          c.firstPage, c.lastPage, c.title, String(c.manual));
      }

      // 首个书签在 p=1 → 第 0 页应成为「卷首」
      expect(chapters.length).assertEqual(9);
      expect(chapters[0].title).assertEqual('卷首');
      expect(chapters[0].firstPage).assertEqual(0);
      expect(chapters[0].lastPage).assertEqual(0);

      // 不变式：按页升序、连续覆盖 [0, n-1]、无重叠无空洞
      expect(chapters[chapters.length - 1].lastPage).assertEqual(n - 1);
      for (let i = 1; i < chapters.length; i++) {
        expect(chapters[i].firstPage).assertEqual(chapters[i - 1].lastPage + 1);
      }
      // 章首页应与去重后的书签页一一对应
      const firsts: Array<number> = [];
      for (const c of chapters) {
        firsts.push(c.firstPage);
      }
      const expected: Array<number> = [0, 1, 3, 4, 5, 6, 9, 16, 18];
      expect(firsts.length).assertEqual(expected.length);
      for (let i = 0; i < expected.length; i++) {
        expect(firsts[i]).assertEqual(expected[i]);
      }
      // 自动分章不应产生 manual 章
      for (const c of chapters) {
        expect(c.manual).assertFalse();
      }
      src.close();
    });
  });
}
