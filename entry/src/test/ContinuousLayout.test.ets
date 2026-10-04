import { describe, it, expect } from '@ohos/hypium';
import { pageOffsets, totalHeight, pageAt } from '../main/ets/reading/ContinuousLayout';

export default function continuousLayoutTest() {
  describe('continuousScroll', () => {
    it('stacks pages with overlap so no line is cut at seams', 0, () => {
      const heights: Array<number> = [100, 100, 100];
      const offsets = pageOffsets(heights, 10);
      expect(offsets.length).assertEqual(3);
      expect(offsets[0]).assertEqual(0);
      expect(offsets[1]).assertEqual(90);
      expect(offsets[2]).assertEqual(180);
    });

    it('computes total scroll height', 0, () => {
      expect(totalHeight([100, 100, 100], 10)).assertEqual(280);
    });

    it('maps scroll position to page index and clamps at edges', 0, () => {
      const offsets: Array<number> = [0, 90, 180];
      expect(pageAt(offsets, 0)).assertEqual(0);
      expect(pageAt(offsets, 89)).assertEqual(0);
      expect(pageAt(offsets, 90)).assertEqual(1);
      expect(pageAt(offsets, 200)).assertEqual(2);
      expect(pageAt(offsets, 999)).assertEqual(2);
      expect(pageAt(offsets, -5)).assertEqual(0);
    });

    it('handles an empty book', 0, () => {
      expect(pageOffsets([], 10).length).assertEqual(0);
      expect(totalHeight([], 10)).assertEqual(0);
      expect(pageAt([], 5)).assertEqual(-1);
    });
  });
}
