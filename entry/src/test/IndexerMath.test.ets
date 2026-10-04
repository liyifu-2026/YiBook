import { describe, it, expect } from '@ohos/hypium';
import { textHash, cacheLookup, planMissing, assembleVectors } from '../main/ets/book/IndexerMath';
import { batchTexts } from '../main/ets/core/Batching';

export default function indexerMathTest() {
  describe('indexerMath', () => {
    it('hash is deterministic and sensitive to content', 0, () => {
      expect(textHash('傅里叶变换') === textHash('傅里叶变换')).assertTrue();
      expect(textHash('傅里叶变换') !== textHash('傅里叶级数')).assertTrue();
      expect(textHash('abc') !== textHash('abcd')).assertTrue();
    });

    it('batches preserve order and cover every item', 0, () => {
      const texts: Array<string> = ['a', 'b', 'c', 'd', 'e'];
      const batches = batchTexts(texts, 2);
      expect(batches.length).assertEqual(3);
      expect(batches[0].length).assertEqual(2);
      expect(batches[2].length).assertEqual(1);
      expect(batches[2][0]).assertEqual('e');
      const flat: Array<string> = [];
      for (const b of batches) {
        for (const t of b) {
          flat.push(t);
        }
      }
      expect(flat.length).assertEqual(5);
      expect(flat[0]).assertEqual('a');
      expect(flat[4]).assertEqual('e');
    });

    it('cache lookup returns vector for known hash, null otherwise', 0, () => {
      const hashes: Array<string> = ['h0', 'h1'];
      const data = new Float32Array([1, 2, 3, 4]);
      const hit = cacheLookup('h1', hashes, data, 2);
      expect(hit !== null).assertTrue();
      if (hit !== null) {
        expect(hit[0]).assertEqual(3);
        expect(hit[1]).assertEqual(4);
      }
      expect(cacheLookup('hX', hashes, data, 2)).assertNull();
      expect(cacheLookup('h0', hashes, data, 0)).assertNull();
    });

    it('planMissing splits cache hits from needs-to-embed', 0, () => {
      const hashes: Array<string> = ['h0', 'h1', 'hX'];
      const data = new Float32Array([1, 2, 3, 4]);
      const plan = planMissing(hashes, ['h0', 'h1'], data, 2);
      expect(plan.missingIdx.length).assertEqual(1);
      expect(plan.missingIdx[0]).assertEqual(2);
      const v = plan.vecs[0];
      expect(v !== null).assertTrue();
      if (v !== null) {
        expect(v[0]).assertEqual(1);
      }
      expect(plan.vecs[2]).assertNull();
    });

    it('assembleVectors packs all vectors and skips mismatches', 0, () => {
      const vecs: Array<Array<number> | null> = [[1, 2], null, [5, 6], [7, 8, 9]];
      const r = assembleVectors(vecs, 2);
      expect(r.embeddedCount).assertEqual(2);
      expect(r.data[0]).assertEqual(1);
      expect(r.data[1]).assertEqual(2);
      expect(r.data[2]).assertEqual(0);
      expect(r.data[3]).assertEqual(0);
      expect(r.data[4]).assertEqual(5);
      expect(r.data[5]).assertEqual(6);
    });
  });
}
