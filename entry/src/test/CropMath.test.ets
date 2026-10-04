import { describe, it, expect } from '@ohos/hypium';
import { findInkBBox, clusterByParity, BBox } from '../main/ets/reading/CropMath';

function assertBBox(actual: BBox | null, l: number, t: number, r: number, b: number) {
  expect(actual !== null).assertTrue();
  if (actual === null) {
    return;
  }
  expect(actual.left).assertEqual(l);
  expect(actual.top).assertEqual(t);
  expect(actual.right).assertEqual(r);
  expect(actual.bottom).assertEqual(b);
}

export default function cropMathTest() {
  describe('whiteEdgeCrop', () => {
    it('finds bbox of an ink rectangle on a white page', 0, () => {
      const w = 10;
      const h = 8;
      const gray = new Uint8Array(w * h).fill(255);
      for (let y = 1; y <= 4; y++) {
        for (let x = 2; x <= 5; x++) {
          gray[y * w + x] = 0;
        }
      }
      assertBBox(findInkBBox(gray, w, h, 128), 2, 1, 5, 4);
    });

    it('counts gray noise below threshold as ink, pure white never', 0, () => {
      const w = 6;
      const h = 4;
      const gray = new Uint8Array(w * h).fill(255);
      gray[2 * w + 3] = 240;
      assertBBox(findInkBBox(gray, w, h, 250), 3, 2, 3, 2);
    });

    it('returns null on a blank page', 0, () => {
      const w = 5;
      const h = 5;
      const gray = new Uint8Array(w * h).fill(254);
      expect(findInkBBox(gray, w, h, 254)).assertNull();
    });

    it('unions crop boxes per page parity', 0, () => {
      const p0: BBox = { left: 2, top: 2, right: 5, bottom: 5 };
      const p1: BBox = { left: 1, top: 1, right: 3, bottom: 3 };
      const p2: BBox = { left: 3, top: 0, right: 6, bottom: 4 };
      const pages: Array<BBox | null> = [p0, p1, p2, null];
      const crop = clusterByParity(pages);
      assertBBox(crop.even, 2, 0, 6, 5);
      assertBBox(crop.odd, 1, 1, 3, 3);
    });

    it('returns null clusters when no page has ink', 0, () => {
      const pages: Array<BBox | null> = [null, null];
      const crop = clusterByParity(pages);
      expect(crop.even).assertNull();
      expect(crop.odd).assertNull();
    });
  });
}
