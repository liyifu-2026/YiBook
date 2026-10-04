import { describe, it, expect } from '@ohos/hypium';
import { isLeftSwipe, extendCap } from '../main/ets/ink/Gestures';

export default function gesturesTest() {
  describe('gestures', () => {
    it('left swipe requires horizontal dominance and threshold', 0, () => {
      expect(isLeftSwipe(-120, 10, 60)).assertTrue();
      expect(isLeftSwipe(-120, -10, 60)).assertTrue();
      expect(isLeftSwipe(120, 0, 60)).assertFalse();
      expect(isLeftSwipe(-50, 0, 60)).assertFalse();
      expect(isLeftSwipe(-120, 100, 60)).assertFalse();
    });

    it('cap extends in batches and clamps to total', 0, () => {
      expect(extendCap(60, 327, 60)).assertEqual(120);
      expect(extendCap(300, 327, 60)).assertEqual(327);
      expect(extendCap(327, 327, 60)).assertEqual(327);
      expect(extendCap(0, 10, 0)).assertEqual(1);
    });
  });
}
