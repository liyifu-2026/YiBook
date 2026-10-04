import { describe, it, expect } from '@ohos/hypium';
import { VectorIndex } from '../main/ets/search/VectorIndex';

export default function vectorIndexTest() {
  describe('vectorIndex', () => {
    it('ranks by cosine similarity and clamps topK', 0, () => {
      const index = new VectorIndex();
      index.add(1, [1, 0]);
      index.add(2, [0.9, 0.1]);
      index.add(3, [0, 1]);
      const hits = index.search([1, 0], 2);
      expect(hits.length).assertEqual(2);
      expect(hits[0]).assertEqual(1);
      expect(hits[1]).assertEqual(2);
      const all = index.search([0, 1], 99);
      expect(all.length).assertEqual(3);
      expect(all[0]).assertEqual(3);
    });
  });
}
