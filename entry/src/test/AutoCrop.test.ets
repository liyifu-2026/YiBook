import { describe, it, expect } from '@ohos/hypium';
import { CROP_DEFAULTS, CropParams, PageScan, PageBox, CropResult, otsuThreshold,
  inkShare, profilesOf, contentBand, scanPage, quantile, bookCrop,
  boxForPage } from '../main/ets/pdf/AutoCrop';

// 造页：白底 255 + 指定归一化矩形内填墨（0）。可选加噪点/整体灰度偏移。
function makePage(w: number, h: number, top: number, bottom: number, left: number,
  right: number, paper: number, ink: number): Uint8Array {
  const g = new Uint8Array(w * h);
  for (let i = 0; i < g.length; i++) {
    g[i] = paper;
  }
  const y0 = Math.floor(top * h);
  const y1 = Math.ceil(bottom * h);
  const x0 = Math.floor(left * w);
  const x1 = Math.ceil(right * w);
  for (let y = y0; y < y1 && y < h; y++) {
    for (let x = x0; x < x1 && x < w; x++) {
      // 隔行填墨，模拟文字行的疏密（不是实心块）
      if (y % 2 === 0) {
        g[y * w + x] = ink;
      }
    }
  }
  return g;
}

function fullPage(w: number, h: number, paper: number): Uint8Array {
  const g = new Uint8Array(w * h);
  for (let i = 0; i < g.length; i++) {
    g[i] = paper;
  }
  return g;
}

// 造「正常书页」：文字块在 top..bottom / left..right，页脚单独一行数字
function normalScan(w: number, h: number, paper: number, ink: number,
  top: number, bottom: number, left: number, right: number): PageScan {
  const g = makePage(w, h, top, bottom, left, right, paper, ink);
  return scanPage(g, w, h, CROP_DEFAULTS);
}

export default function autoCropTest() {
  const W = 160;
  const H = 224;

  describe('autoCrop.threshold', () => {
    it('Otsu splits ink from paper without any hardcoded gray level', 0, () => {
      // 二分灰度直方图下 Otsu 的极值出现在两种灰之间，实现取第一个极值点
      //（即墨色本身）：ink = gray <= 阈值 仍然只圈住墨。断言用 >= 而不是 >。
      const light = makePage(W, H, 0.1, 0.9, 0.1, 0.9, 240, 40);
      const tLight = otsuThreshold(light);
      expect(tLight >= 40 && tLight < 240).assertTrue();
      // 偏暗的扫描件（纸 170 / 字 60）——固定阈值 180 在这里会把整页判成墨
      const dark = makePage(W, H, 0.1, 0.9, 0.1, 0.9, 170, 60);
      const tDark = otsuThreshold(dark);
      expect(tDark >= 60 && tDark < 170).assertTrue();
      // 自适应阈值下，「墨」只有文字块那一部分
      expect(inkShare(dark, tDark) < 0.6).assertTrue();
      // 反面证据：拿旧的固定阈值 180 去量同一张暗页，几乎整页都会被算成墨
      expect(inkShare(dark, 180) > 0.95).assertTrue();
    });
  });

  describe('autoCrop.profiles', () => {
    it('sliding-window band ignores isolated speckle rows', 0, () => {
      const p: Array<number> = [];
      for (let i = 0; i < 100; i++) {
        p.push(0);
      }
      p[3] = 0.5;           // 孤立噪点行
      for (let i = 40; i < 60; i++) {
        p[i] = 0.3;         // 真正的文本块
      }
      const band = contentBand(p, 0.02, 3);
      expect(band !== null).assertTrue();
      if (band !== null) {
        expect(band.lo).assertEqual(40);
        expect(band.hi).assertEqual(59);
      }
    });

    it('all-blank profile yields no band', 0, () => {
      const p: Array<number> = [];
      for (let i = 0; i < 50; i++) {
        p.push(0);
      }
      expect(contentBand(p, 0.02, 3)).assertNull();
    });
  });

  describe('autoCrop.scanPage', () => {
    it('finds the content box of a normal text page', 0, () => {
      const s = normalScan(W, H, 245, 30, 0.08, 0.94, 0.09, 0.91);
      expect(s.box !== null).assertTrue();
      if (s.box !== null) {
        expect(Math.abs(s.box.top - 0.08) < 0.02).assertTrue();
        expect(Math.abs(s.box.bottom - 0.94) < 0.02).assertTrue();
        expect(Math.abs(s.box.left - 0.09) < 0.02).assertTrue();
        expect(Math.abs(s.box.right - 0.91) < 0.02).assertTrue();
      }
    });

    it('skips blank and photo pages so they cannot poison the book box', 0, () => {
      const blank = scanPage(fullPage(W, H, 250), W, H, CROP_DEFAULTS);
      expect(blank.box).assertNull();
      const photo = makePage(W, H, 0, 1, 0, 1, 255, 0);   // 满版黑
      const ph = scanPage(photo, W, H, CROP_DEFAULTS);
      expect(ph.box).assertNull();
    });

    it('detects a two-page spread from the blank gutter', 0, () => {
      // 左半页与右半页各有文字块，中间中缝留空
      const g = fullPage(W, H, 245);
      const left = makePage(W, H, 0.1, 0.9, 0.05, 0.46, 245, 30);
      const right = makePage(W, H, 0.1, 0.9, 0.54, 0.95, 245, 30);
      for (let i = 0; i < g.length; i++) {
        g[i] = left[i] < g[i] ? left[i] : g[i];
        g[i] = right[i] < g[i] ? right[i] : g[i];
      }
      const s = scanPage(g, W, H, CROP_DEFAULTS);
      expect(s.spread).assertTrue();
    });
  });

  describe('autoCrop.robustEdges', () => {
    it('quantile is unmoved by a few wild pages', 0, () => {
      const xs: Array<number> = [0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.0, 1.0];
      expect(Math.abs(quantile(xs, 0.25) - 0.10) < 0.001).assertTrue();
      expect(Math.abs(quantile(xs, 0.75) - 0.10) < 0.001).assertTrue();
      // 并集（min/max）则会被那两个离群值拽到两端
      let lo = 1;
      let hi = 0;
      for (const v of xs) {
        if (v < lo) { lo = v; }
        if (v > hi) { hi = v; }
      }
      expect(lo).assertEqual(0);
      expect(hi).assertEqual(1);
    });

    // 真机教训：这本扫描件**顶边**近一半页有墨（扫描黑边/出血装饰），
    // 但**左右边距**很一致。四条边绑在一起判"版式是否一致"会互相否决、一页都裁不了；
    // 分开估计之后，左右照样裁得干净，顶边则诚实地不裁。
    it('a messy top edge does not veto a clean left/right crop', 0, () => {
      const scans: Array<PageScan> = [];
      for (let i = 0; i < 24; i++) {
        const top = i < 11 ? 0.0 : 0.05;
        scans.push(normalScan(W, H, 245, 30, top, 0.97, 0.085, 0.925));
      }
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.shared !== null).assertTrue();
      if (r.shared !== null) {
        // 顶边：多数页并不一致（近半贴边）→ 不裁，如实保留
        expect(r.shared.top < 0.03).assertTrue();
        // 左右：一致 → 必须裁掉
        expect(r.shared.left > 0.06).assertTrue();
        expect(r.shared.right < 0.95).assertTrue();
      }
    });

    it('keeps the crop tight when only a minority bleeds to the edge', 0, () => {
      const scans: Array<PageScan> = [];
      for (let i = 0; i < 15; i++) {
        scans.push(normalScan(W, H, 245, 30, 0.08, 0.92, 0.09, 0.91));
      }
      for (const k of [2, 7, 11]) {
        scans[k] = normalScan(W, H, 245, 30, 0.0, 1.0, 0.0, 1.0);
      }
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.shared !== null).assertTrue();
      if (r.shared !== null) {
        expect(r.shared.top > 0.05).assertTrue();
        expect(r.shared.bottom < 0.95).assertTrue();
      }
    });
  });

  describe('autoCrop.bookCrop', () => {

    it('refuses to crop when there is no dominant layout at all', 0, () => {
      const scans: Array<PageScan> = [];
      // 每页版心都不同：没有"多数页一致"这件事，就不该硬裁
      for (let i = 0; i < 9; i++) {
        const t = 0.02 + i * 0.05;
        scans.push(normalScan(W, H, 245, 30, t, 0.98, 0.02 + i * 0.05, 0.98));
      }
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.shared).assertNull();
    });

    it('caps the trim instead of slicing half a page', 0, () => {
      const scans: Array<PageScan> = [];
      // 主流页版心偏到只占页面下半（顶边要裁 40%）→ 必须夹到 maxTrim 而不是照裁
      for (let i = 0; i < 10; i++) {
        scans.push(normalScan(W, H, 245, 30, 0.40, 0.96, 0.05, 0.95));
      }
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.shared !== null).assertTrue();
      if (r.shared !== null) {
        expect(r.shared.top <= CROP_DEFAULTS.maxTrim + 0.0001).assertTrue();
      }
    });
    it('uses one box for the whole book when margins are consistent', 0, () => {
      const scans: Array<PageScan> = [];
      for (let i = 0; i < 12; i++) {
        scans.push(normalScan(W, H, 245, 30, 0.08, 0.94, 0.09, 0.91));
      }
      const r: CropResult = bookCrop(scans, CROP_DEFAULTS);
      expect(r.split).assertFalse();
      expect(r.shared !== null).assertTrue();
      expect(r.spread).assertFalse();
    });

    it('survives one full-bleed illustration among normal pages', 0, () => {
      const scans: Array<PageScan> = [];
      for (let i = 0; i < 14; i++) {
        scans.push(normalScan(W, H, 245, 30, 0.10, 0.90, 0.10, 0.90));
      }
      scans[5] = scanPage(makePage(W, H, 0.0, 1.0, 0.0, 1.0, 245, 30), W, H, CROP_DEFAULTS);
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.shared !== null).assertTrue();
      if (r.shared !== null) {
        // 仍然贴着正常页的版心，没有被出血页撑开
        expect(r.shared.left > 0.08).assertTrue();
        expect(r.shared.right < 0.92).assertTrue();
        expect(r.shared.top > 0.08).assertTrue();
      }
    });

    it('gives up on cropping (rather than cropping wrong) for a spread-scan book', 0, () => {
      const scans: Array<PageScan> = [];
      const g = fullPage(W, H, 245);
      const left = makePage(W, H, 0.1, 0.9, 0.05, 0.46, 245, 30);
      const right = makePage(W, H, 0.1, 0.9, 0.54, 0.95, 245, 30);
      for (let i = 0; i < g.length; i++) {
        g[i] = left[i] < g[i] ? left[i] : g[i];
        g[i] = right[i] < g[i] ? right[i] : g[i];
      }
      for (let i = 0; i < 8; i++) {
        scans.push(scanPage(g, W, H, CROP_DEFAULTS));
      }
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.spread).assertTrue();
      expect(r.shared).assertNull();
    });

    it('splits even/odd only when the margins really differ', 0, () => {
      const scans: Array<PageScan> = [];
      for (let i = 0; i < 12; i++) {
        // 偶数页版心偏上、奇数页偏下 —— 装订边交替的书
        if (i % 2 === 0) {
          scans.push(normalScan(W, H, 245, 30, 0.06, 0.80, 0.09, 0.91));
        } else {
          scans.push(normalScan(W, H, 245, 30, 0.18, 0.94, 0.09, 0.91));
        }
      }
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.split).assertTrue();
      expect(r.even !== null && r.odd !== null).assertTrue();
      const b0 = boxForPage(r, 0);
      const b1 = boxForPage(r, 1);
      expect(b0 !== null && b1 !== null).assertTrue();
      if (b0 !== null && b1 !== null) {
        expect(b1.top > b0.top).assertTrue();
      }
    });

    it('refuses an implausible box (never worse than no crop)', 0, () => {
      const scans: Array<PageScan> = [];
      // 内容只占页面中间一条 → 触发 minHeight 兜底
      for (let i = 0; i < 8; i++) {
        scans.push(normalScan(W, H, 245, 30, 0.45, 0.55, 0.45, 0.55));
      }
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.shared).assertNull();
    });
  });

  describe('autoCrop.edgeCases', () => {
    it('a single page is not enough evidence to crop', 0, () => {
      const scans: Array<PageScan> = [];
      scans.push(normalScan(W, H, 245, 30, 0.1, 0.9, 0.1, 0.9));
      expect(bookCrop(scans, CROP_DEFAULTS).shared).assertNull();
    });

    it('two consistent pages are enough (short documents still get cropped)', 0, () => {
      const scans: Array<PageScan> = [];
      scans.push(normalScan(W, H, 245, 30, 0.1, 0.9, 0.1, 0.9));
      scans.push(normalScan(W, H, 245, 30, 0.1, 0.9, 0.1, 0.9));
      const r = bookCrop(scans, CROP_DEFAULTS);
      expect(r.shared !== null).assertTrue();
    });
  });
}
