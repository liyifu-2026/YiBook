import { describe, it, expect } from '@ohos/hypium';
import { buildPageChunks, visibleChunks, pagesToRelease, PageChunk,
  CHUNK_MAX_VP, CHUNK_WINDOW_MARGIN } from '../main/ets/pdf/ChunkWindow';
import { PageRange } from '../main/ets/pdf/RenderWindow';

// 长卷分块与渲染窗口的行为网。
// 这些不变量是用一次「整卷空白」换来的（GPU 纹理上限），必须由测试守住。

function topsOf(heights: Array<number>): Array<number> {
  const tops: Array<number> = [];
  let y = 0;
  for (const h of heights) {
    tops.push(y);
    y += h;
  }
  return tops;
}

function totalHeight(chunks: Array<PageChunk>): number {
  let t = 0;
  for (const c of chunks) {
    t += c.height;
  }
  return t;
}

export default function chunkWindowTest() {
  describe('chunkWindow', () => {

    it('splits a tall stack so no multi-page chunk exceeds the GPU-safe height', 0, () => {
      // 复现 24 页教材场景：16377vp 的整卷曾整块不渲染
      const heights: Array<number> = [];
      for (let i = 0; i < 24; i++) {
        heights.push(682);
      }
      const tops = topsOf(heights);
      const chunks = buildPageChunks(tops, heights, CHUNK_MAX_VP);

      expect(chunks.length > 1).assertTrue();
      for (const c of chunks) {
        if (c.pages.length > 1) {
          expect(c.height <= CHUNK_MAX_VP).assertTrue();
        }
      }
      // 每页恰好属于一个块，且顺序不变
      const seen: Array<number> = [];
      for (const c of chunks) {
        for (const p of c.pages) {
          seen.push(p);
        }
      }
      expect(seen.length).assertEqual(24);
      for (let i = 0; i < 24; i++) {
        expect(seen[i]).assertEqual(i);
      }
      // 总高不变 → 长卷仍能滚到底
      expect(totalHeight(chunks)).assertEqual(24 * 682);
    });

    it('handles an empty book and a single oversized page', 0, () => {
      expect(buildPageChunks([], [], CHUNK_MAX_VP).length).assertEqual(0);
      // 单页自身超高时不再切分（切了也无意义）
      const one = buildPageChunks([0], [2000], CHUNK_MAX_VP);
      expect(one.length).assertEqual(1);
      expect(one[0].height).assertEqual(2000);
      expect(one[0].pages.length).assertEqual(1);
    });

    it('keeps every chunk in the scroll content but empties the off-window ones', 0, () => {
      const heights: Array<number> = [400, 400, 400];
      const tops = topsOf(heights);
      const chunks = buildPageChunks(tops, heights, 500); // 强制一页一块
      expect(chunks.length).assertEqual(3);
      const ready: Array<boolean> = [true, true, true];

      const vis = visibleChunks(chunks, 0, 400, ready, CHUNK_WINDOW_MARGIN);
      expect(vis.length).assertEqual(3);
      // 窗内块保留页
      expect(vis[0].pages.length).assertEqual(1);
      // 窗外块保留高度（撑起整卷可滚）但清空页（无绘制内容，不触发纹理上限）
      expect(vis[2].pages.length).assertEqual(0);
      expect(vis[2].height).assertEqual(400);
      // 关键不变量：滚动位置不影响内容总高
      const far = visibleChunks(chunks, 100000, 400, ready, CHUNK_WINDOW_MARGIN);
      expect(totalHeight(vis)).assertEqual(totalHeight(far));
      expect(totalHeight(far)).assertEqual(1200);
    });

    it('flips imgKey only when the whole chunk is ready and inside the window', 0, () => {
      const heights: Array<number> = [200, 200, 200];
      const tops = topsOf(heights);
      const chunks = buildPageChunks(tops, heights, 500);
      // 块0 = [0,1]，块1 = [2]
      expect(chunks[0].pages.length).assertEqual(2);

      const partial = visibleChunks(chunks, 0, 400, [true, false, true], CHUNK_WINDOW_MARGIN);
      expect(partial[0].imgKey).assertEqual(0);
      const full = visibleChunks(chunks, 0, 400, [true, true, true], CHUNK_WINDOW_MARGIN);
      expect(full[0].imgKey).assertEqual(1);
      expect(full[1].imgKey).assertEqual(1);

      // 窗外即使全就绪也不翻转（避免滚动时反复重挂画布）
      const outside = visibleChunks(chunks, 100000, 400, [true, true, true], CHUNK_WINDOW_MARGIN);
      expect(outside[0].imgKey).assertEqual(0);
      expect(outside[0].pages.length).assertEqual(0);
    });

    it('releases exactly the loaded pages outside the render window plus margin', 0, () => {
      const loaded: Array<boolean> = [true, true, true, true, true];
      const range: PageRange = { first: 2, last: 2 };
      const rel = pagesToRelease(range, loaded, 1);
      expect(rel.length).assertEqual(2);
      expect(rel[0]).assertEqual(0);
      expect(rel[1]).assertEqual(4);

      // 余量放大到 2 → 窗外无页
      expect(pagesToRelease(range, loaded, 2).length).assertEqual(0);
      // 余量 0 → 连窗内两侧也放掉
      const tight = pagesToRelease(range, loaded, 0);
      expect(tight.length).assertEqual(4);

      // 未加载的页不需要释放
      expect(pagesToRelease(range, [false, true, true, true, false], 1).length).assertEqual(0);
      // 空窗口（书未就绪）不释放任何东西
      expect(pagesToRelease({ first: -1, last: -1 }, loaded, 1).length).assertEqual(0);
    });
  });
}
