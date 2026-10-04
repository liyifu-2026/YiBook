import { describe, it, expect } from '@ohos/hypium';
import { transformForCrop, toPagePoint, DisplayTransform } from '../main/ets/pdf/ReaderGeometry';
import { BBox } from '../main/ets/pdf/CropMath';

export default function readerGeometryTest() {
  describe('readerGeometry', () => {
    it('fit-width transform shrinks page by crop and offsets origin', 0, () => {
      const crop: BBox = { left: 10, top: 10, right: 601, bottom: 781 };
      const t: DisplayTransform = transformForCrop(612, 792, crop, 296);
      expect(t.scale).assertClose(0.5, 0.000001);
      expect(t.offsetX).assertClose(-5, 0.000001);
      expect(t.offsetY).assertClose(-5, 0.000001);
      expect(t.contentHeight).assertClose(386, 0.000001);
    });

    it('maps screen point back to original page coords for anchors', 0, () => {
      const crop: BBox = { left: 10, top: 10, right: 601, bottom: 781 };
      const t: DisplayTransform = transformForCrop(612, 792, crop, 296);
      const p = toPagePoint(t, 147, 195);
      expect(p.x).assertClose(304, 0.000001);
      expect(p.y).assertClose(400, 0.000001);
    });

    it('uncropped page maps full width', 0, () => {
      const t: DisplayTransform = transformForCrop(612, 792, null, 306);
      expect(t.scale).assertClose(0.5, 0.000001);
      expect(t.offsetX).assertClose(0, 0.000001);
      expect(t.offsetY).assertClose(0, 0.000001);
      expect(t.contentHeight).assertClose(396, 0.000001);
    });
  });
}
