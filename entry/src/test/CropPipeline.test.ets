import { describe, it, expect } from '@ohos/hypium';
import { downsampleGrid, parityCropFor, sampleToPagePoint, regionForBBox, regionHint, SampleGrid } from '../main/ets/pdf/CropPipeline';
import { BBox, ParityCrop } from '../main/ets/pdf/CropMath';

export default function cropPipelineTest() {
  describe('cropPipeline', () => {
    it('caps sampling grid resolution while covering the whole page', 0, () => {
      const big: SampleGrid = downsampleGrid(2480, 3508, 200);
      expect(big.stepX).assertEqual(13);
      expect(big.stepY).assertEqual(18);
      expect(big.cols).assertEqual(191);
      expect(big.rows).assertEqual(195);
      const small: SampleGrid = downsampleGrid(100, 50, 200);
      expect(small.cols).assertEqual(100);
      expect(small.rows).assertEqual(50);
      expect(small.stepX).assertEqual(1);
      expect(small.stepY).assertEqual(1);
    });

    it('first page uses the even cluster, second the odd', 0, () => {
      const even: BBox = { left: 2, top: 0, right: 6, bottom: 5 };
      const odd: BBox = { left: 1, top: 1, right: 3, bottom: 3 };
      const parity: ParityCrop = { even: even, odd: odd };
      expect(parityCropFor(0, parity)).assertEqual(even);
      expect(parityCropFor(1, parity)).assertEqual(odd);
      expect(parityCropFor(2, parity)).assertEqual(even);
    });

    it('converts sample cell center to page coordinates', 0, () => {
      const grid: SampleGrid = downsampleGrid(2480, 3508, 200);
      const p = sampleToPagePoint(95, 100, grid, 2480, 3508);
      expect(p.x).assertClose((95 + 0.5) * 13, 0.000001);
      expect(p.y).assertClose((100 + 0.5) * 18, 0.000001);
      const last = sampleToPagePoint(grid.cols - 1, grid.rows - 1, grid, 2480, 3508);
      expect(last.x < 2480).assertTrue();
      expect(last.y < 3508).assertTrue();
    });

    it('ocr region pads the gesture box and clamps to the page', 0, () => {
      const grid: SampleGrid = downsampleGrid(1000, 1000, 100); // step 10
      const bbox: BBox = { left: 2, top: 3, right: 5, bottom: 6 };
      const r = regionForBBox(bbox, grid, 1000, 1000, 0.5);
      expect(r.x).assertEqual(0);
      expect(r.y).assertEqual(10);
      expect(r.width).assertEqual(80);
      expect(r.height).assertEqual(80);
      const edge: BBox = { left: 0, top: 0, right: 1, bottom: 1 };
      const r2 = regionForBBox(edge, grid, 100, 100, 0.5);
      expect(r2.x).assertEqual(0);
      expect(r2.y).assertEqual(0);
      expect(r2.width).assertEqual(40);
      expect(r2.height).assertEqual(40);
    });

    it('region hint describes the circled band in page percentages', 0, () => {
      const grid: SampleGrid = downsampleGrid(1000, 1000, 100); // step 10
      const bbox: BBox = { left: 10, top: 20, right: 39, bottom: 49 };
      const hint = regionHint(bbox, grid, 1000, 1000);
      expect(hint.indexOf('20%') >= 0 && hint.indexOf('50%') >= 0).assertTrue();
      expect(hint.indexOf('纵向') >= 0 && hint.indexOf('横向') >= 0).assertTrue();
    });
  });
}
