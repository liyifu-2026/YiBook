import { describe, it, expect } from '@ohos/hypium';
import { renderWindow, absoluteScrollOffset } from '../main/ets/pdf/RenderWindow';

export default function renderWindowTest() {
  describe('renderWindow', () => {
    it('covers visible pages plus prerender margin, clamped', 0, () => {
      const offsets: Array<number> = [0, 90, 180];
      const r0 = renderWindow(offsets, 0, 120, 1);
      expect(r0.first).assertEqual(0);
      expect(r0.last).assertEqual(2);
      const r1 = renderWindow(offsets, 100, 120, 1);
      expect(r1.first).assertEqual(0);
      expect(r1.last).assertEqual(2);
      const r2 = renderWindow(offsets, 150, 120, 1);
      expect(r2.first).assertEqual(0);
      expect(r2.last).assertEqual(2);
    });

    it('empty book yields empty window', 0, () => {
      const r = renderWindow([], 50, 120, 1);
      expect(r.first).assertEqual(-1);
      expect(r.last).assertEqual(-1);
    });
  });

  // 回归守卫：Scroll.onScroll 的第二个入参是**相对上一帧的增量**，不是绝对位置。
  // 实测 bug：把它当绝对位置（scrollY = delta）→ scrollY 恒为 1.2~2.0vp →
  // 渲染窗口永远算在 y≈0 → 整本书只有第一块有内容，往下一片空白且页码恒为 P1。
  describe('absoluteScrollOffset', () => {
    it('trusts the container: the delta is never promoted to a position', 0, () => {
      // 容器报 5000，增量只有 1.6 —— 位置必须取 5000，绝不能是 1.6
      expect(absoluteScrollOffset(5000, 4998.4, 1.6)).assertEqual(5000);
      // 回弹到 0 也要如实上报（0 是合法位置，不能被当成「拿不到」）
      expect(absoluteScrollOffset(0, 12.8, -12.8)).assertEqual(0);
    });

    it('feeding a delta as the position pins the window at the top', 0, () => {
      // 这就是那个 bug 的纯逻辑画像：每帧「增量」都被当成位置。
      const pageTops: Array<number> = [0, 700, 1400, 2100, 2800, 3500];
      const deltas: Array<number> = [30, 30, 30, 30, 30];
      let buggyY = 0;
      const buggyFirst: Array<number> = [];
      for (const d of deltas) {
        buggyY = absoluteScrollOffset(d, buggyY, d);
        buggyFirst.push(renderWindow(pageTops, buggyY, 1000, 1).first);
      }
      // 位置永远停在 30 附近 → 窗口永远从第 0 页开始
      expect(buggyFirst[buggyFirst.length - 1]).assertEqual(0);
      // 换成容器上报的绝对位置，窗口必须跟着推进到后面几页
      // （pageTops=[0,700,1400,2100,2800,3500]，viewport 1000，prerender 1）
      const realY: Array<number> = [30, 2000, 4000];
      expect(renderWindow(pageTops, realY[0], 1000, 1).first).assertEqual(0);
      expect(renderWindow(pageTops, realY[1], 1000, 1).first).assertEqual(1);
      expect(renderWindow(pageTops, realY[2], 1000, 1).first).assertEqual(4);
    });

    it('falls back to accumulating deltas only when the container cannot report', 0, () => {
      expect(absoluteScrollOffset(Number.NaN, 400, 30)).assertEqual(430);
      expect(absoluteScrollOffset(-1, 400, 30)).assertEqual(430);
      // 兜底也不许产生负数位置
      expect(absoluteScrollOffset(Number.NaN, 10, -50)).assertEqual(10);
      expect(absoluteScrollOffset(Number.NaN, 5, Number.NaN)).assertEqual(5);
    });
  });
}
