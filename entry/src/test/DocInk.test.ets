import { describe, it, expect } from '@ohos/hypium';
import { DocLayout, DocPoint, DocStroke, INK_PLAIN, INK_AI,
  pageTopOf, docHeightOf, pageIndexAt, localYInPage, docYOf,
  pagesOfStroke, isCrossPage, anchorPageOf, boxOfStroke, strokeHits,
  findHitStroke, simplify, strokesToJson, strokesFromJson } from '../main/ets/ink/DocInk';

function stroke(id: number, pts: Array<DocPoint>, w: number): DocStroke {
  const s: DocStroke = { id: id, points: pts, color: '#000000', width: w, kind: INK_PLAIN };
  return s;
}

export default function docInkTest() {
  // 一页 1000 高、缝 20、共 5 页
  const L: DocLayout = { pageW: 600, pageH: 1000, gap: 20, count: 5 };

  describe('docInk.pageMath', () => {
    it('page tops follow pageH + gap stride', 0, () => {
      expect(pageTopOf(L, 0)).assertEqual(0);
      expect(pageTopOf(L, 1)).assertEqual(1020);
      expect(pageTopOf(L, 3)).assertEqual(3060);
    });

    it('total height is last page bottom', 0, () => {
      expect(docHeightOf(L)).assertEqual(4 * 1020 + 1000);
    });

    it('maps a document y back to page and local y', 0, () => {
      // 第 2 页（顶边 2040）内 300 处
      expect(pageIndexAt(L, 2340)).assertEqual(2);
      expect(localYInPage(L, 2340)).assertEqual(300);
      expect(docYOf(L, 2, 300)).assertEqual(2340);
    });

    it('a point falling in the seam belongs to the previous page', 0, () => {
      // 第 1 页顶边 1020，页底 2020，缝 [2020,2040)
      expect(pageIndexAt(L, 2030)).assertEqual(1);
      // 缝里的点贴到最近页边，而不是算出越界的页内坐标
      expect(localYInPage(L, 2030)).assertEqual(1000);
    });

    it('clamps out-of-range y instead of returning bogus pages', 0, () => {
      expect(pageIndexAt(L, -50)).assertEqual(0);
      expect(pageIndexAt(L, 999999)).assertEqual(4);
    });
  });

  describe('docInk.crossPage', () => {
    // 这是本轮的核心诉求：一笔从第 1 页末尾写到第 2 页开头，必须被认定为跨页，
    // 而不是在页边被切断成两笔。
    const s = stroke(1, [
      { x: 100, y: 1900 },   // 第 1 页内
      { x: 120, y: 2010 },   // 第 1 页末尾
      { x: 140, y: 2030 },   // 页缝里
      { x: 160, y: 2100 },   // 第 2 页开头
      { x: 180, y: 2200 }
    ], 4);

    it('a stroke crossing the seam reports both pages', 0, () => {
      const pages = pagesOfStroke(L, s);
      expect(pages.length).assertEqual(2);
      expect(pages[0]).assertEqual(1);
      expect(pages[1]).assertEqual(2);
      expect(isCrossPage(L, s)).assertTrue();
    });

    it('anchors to the page under the middle of the stroke', 0, () => {
      // 5 个点，中点是 index 2 -> y=2030 -> 归第 1 页
      expect(anchorPageOf(L, s)).assertEqual(1);
    });

    it('a stroke inside one page is not cross-page', 0, () => {
      const one = stroke(2, [{ x: 10, y: 100 }, { x: 20, y: 900 }], 4);
      expect(isCrossPage(L, one)).assertFalse();
      expect(pagesOfStroke(L, one)[0]).assertEqual(0);
    });
  });

  describe('docInk.geometry', () => {
    it('bounding box covers every point', 0, () => {
      const s = stroke(1, [{ x: 5, y: 300 }, { x: -2, y: 100 }, { x: 40, y: 250 }], 2);
      const b = boxOfStroke(s);
      expect(b.left).assertEqual(-2);
      expect(b.right).assertEqual(40);
      expect(b.top).assertEqual(100);
      expect(b.bottom).assertEqual(300);
    });

    it('hit test uses stroke width as tolerance', 0, () => {
      const s = stroke(1, [{ x: 0, y: 0 }, { x: 100, y: 0 }], 10);
      // 距线段 4px：笔宽 10 -> 半径 5，加上容差 0 也应命中
      expect(strokeHits(s, { x: 50, y: 4 }, 0)).assertTrue();
      // 距线段 20px：超出，不命中
      expect(strokeHits(s, { x: 50, y: 20 }, 0)).assertFalse();
      // 给容差 20 就命中了（橡皮擦用）
      expect(strokeHits(s, { x: 50, y: 20 }, 20)).assertTrue();
    });

    it('erases the topmost hit stroke only', 0, () => {
      const a = stroke(1, [{ x: 0, y: 0 }, { x: 100, y: 0 }], 10);
      const b = stroke(2, [{ x: 0, y: 2 }, { x: 100, y: 2 }], 10);
      const list: Array<DocStroke> = [a, b];
      // 两笔都命中时，擦最上面那一笔（后画的）
      expect(findHitStroke(list, { x: 50, y: 1 }, 3)).assertEqual(1);
      // 擦不到就返回 -1
      expect(findHitStroke(list, { x: 50, y: 500 }, 3)).assertEqual(-1);
    });

    it('simplify thins dense samples but keeps the last point', 0, () => {
      const pts: Array<DocPoint> = [
        { x: 0, y: 0 }, { x: 0.5, y: 0 }, { x: 0.8, y: 0 },
        { x: 10, y: 0 }, { x: 10.4, y: 0 }, { x: 21, y: 3 }
      ];
      const out = simplify(pts, 2);
      expect(out.length < pts.length).assertTrue();
      expect(out[0].x).assertEqual(0);
      const last = out[out.length - 1];
      expect(last.x).assertEqual(21);
      expect(last.y).assertEqual(3);
    });
  });

  describe('docInk.persistence', () => {
    it('round-trips strokes including a cross-page one', 0, () => {
      const list: Array<DocStroke> = [
        stroke(7, [{ x: 1.25, y: 2.5 }, { x: 3, y: 4 }], 3),
        { id: 8, points: [{ x: 10, y: 2030 }, { x: 12, y: 2100 }],
          color: '#4C9AFF', width: 6, kind: INK_AI }
      ];
      const text = strokesToJson(list);
      const back = strokesFromJson(text);
      expect(back.length).assertEqual(2);
      expect(back[0].id).assertEqual(7);
      expect(back[0].points.length).assertEqual(2);
      expect(back[0].points[0].x).assertEqual(1.3);
      expect(back[1].kind).assertEqual(INK_AI);
      expect(back[1].color).assertEqual('#4C9AFF');
      // 跨页属性在往返后依然成立
      expect(isCrossPage(L, back[1])).assertTrue();
    });

    it('empty or broken json yields an empty list, never throws', 0, () => {
      expect(strokesFromJson('').length).assertEqual(0);
      expect(strokesFromJson('not json').length).assertEqual(0);
    });
  });
}
