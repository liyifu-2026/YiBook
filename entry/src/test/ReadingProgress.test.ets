import { describe, it, expect } from '@ohos/hypium';
import { updateHighWater } from '../main/ets/book/ReadingProgress';

export default function readingProgressTest() {
  describe('readingProgress', () => {
    it('high water mark only moves forward', 0, () => {
      expect(updateHighWater(0, 3)).assertEqual(3);
      expect(updateHighWater(3, 5)).assertEqual(5);
      expect(updateHighWater(5, 3)).assertEqual(5);
      expect(updateHighWater(5, 5)).assertEqual(5);
    });
  });
}
