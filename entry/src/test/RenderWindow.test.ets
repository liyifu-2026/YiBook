import { describe, it, expect } from '@ohos/hypium';
import { renderWindow } from '../main/ets/reading/RenderWindow';

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
}
