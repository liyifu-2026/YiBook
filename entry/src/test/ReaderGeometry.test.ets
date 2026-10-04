import { describe, it, expect } from '@ohos/hypium';
import { transformForCrop, toPagePoint, DisplayTransform } from '../main/ets/pdf/ReaderGeometry';
import { BBox } from '../main/ets/pdf/CropMath';
import { downsampleGrid, SampleGrid } from '../main/ets/pdf/CropPipeline';

export default function readerGeometryTest() {
  describe('readerGeometry', () => {
    it('fit-width transform shrinks page by crop and offsets origin', 0, () => {
      // 裁剪框与页面同为单位（像素步长 1）：这正是老用例的隐含假设
      const crop: BBox = { left: 10, top: 10, right: 601, bottom: 781 };
      const t: DisplayTransform = transformForCrop(612, 792, crop, 296, 1, 1);
      expect(t.scale).assertClose(0.5, 0.000001);
      expect(t.offsetX).assertClose(-5, 0.000001);
      expect(t.offsetY).assertClose(-5, 0.000001);
      expect(t.contentHeight).assertClose(386, 0.000001);
    });

    it('maps screen point back to original page coords for anchors', 0, () => {
      const crop: BBox = { left: 10, top: 10, right: 601, bottom: 781 };
      const t: DisplayTransform = transformForCrop(612, 792, crop, 296, 1, 1);
      const p = toPagePoint(t, 147, 195);
      expect(p.x).assertClose(304, 0.000001);
      expect(p.y).assertClose(400, 0.000001);
    });

    it('uncropped page maps full width', 0, () => {
      const t: DisplayTransform = transformForCrop(612, 792, null, 306, 1, 1);
      expect(t.scale).assertClose(0.5, 0.000001);
      expect(t.offsetX).assertClose(0, 0.000001);
      expect(t.offsetY).assertClose(0, 0.000001);
      expect(t.contentHeight).assertClose(396, 0.000001);
    });

    // 采样栅格的 stepX/stepY 不相等（栅格固定约 160×160，页面却是 594×840），
    // 所以「栅格行」与「栅格列」不是同一长度单位。裁剪框来自栅格坐标，
    // 换算成显示尺寸时必须各用各的步长——否则槽位高度会小 stepY/stepX 倍，
    // Image 被塞进比例错误的盒子，**每一页的上下都被切掉**（真机实测槽高 691.5vp，
    // 而该页按真实像素比例应为约 983vp）。
    it('grid crop converts with per-axis steps, not one isotropic scale', 0, () => {
      const grid: SampleGrid = downsampleGrid(1191, 1684, 160);
      // 全页裁剪框（栅格坐标）
      const crop: BBox = { left: 0, top: 0, right: grid.cols - 1, bottom: grid.rows - 1 };
      const cropPxW = grid.cols * grid.stepX;
      const cropPxH = grid.rows * grid.stepY;
      const viewWidth = 736;
      const t: DisplayTransform = transformForCrop(cropPxW, cropPxH, crop, viewWidth,
        grid.stepX, grid.stepY);
      // 显示比例 = vp / 像素
      expect(t.scale).assertClose(viewWidth / cropPxW, 0.0000001);
      // 内容高必须等于「以真实像素纵横比」缩放的结果
      expect(t.contentHeight).assertClose(viewWidth * cropPxH / cropPxW, 0.001);
      // 且明显大于「忽略各向异性」的错误值——这就是被切掉的那部分
      const isotropic = (grid.rows) * (viewWidth / grid.cols);
      expect(t.contentHeight > isotropic * 1.2).assertTrue();
    });
  });
}
