import { BBox } from './CropMath';

export interface DisplayTransform {
  scale: number;
  offsetX: number;
  offsetY: number;
  contentHeight: number;
}

export interface PagePoint {
  x: number;
  y: number;
}

// 裁剪框来自**采样栅格坐标**（pdf/CropPipeline.SampleGrid）。栅格被固定成约 160×160，
// 而页面是 594×840，所以 grid.stepY ≠ grid.stepX：一个栅格行与一个栅格列**不是同一长度**。
// 因此换算必须各轴用各自步长（stepX 管横向、stepY 管纵向），否则槽位高度会小
// stepY/stepX 倍（本机 ≈1.37）。后果不是「稍微不准」，而是 Image 被塞进比例错误的盒子，
// **每一页的上下都被切掉**（真机实测槽高 691.5vp，按真实像素比例应为约 983vp）。
// 与 pdf/PdfPageSource.cropPage 的换算（x/w 用 stepX、h 用 stepY）必须保持一致，
// 否则「位图裁了什么」与「版式以为裁了什么」会各说各话。
export function transformForCrop(pageWidthPx: number, pageHeightPx: number,
  crop: BBox | null, viewWidth: number, stepX: number, stepY: number): DisplayTransform {
  if (crop === null) {
    const scale = pageWidthPx > 0 ? viewWidth / pageWidthPx : 1;
    const t: DisplayTransform = {
      scale: scale,
      offsetX: 0,
      offsetY: 0,
      contentHeight: pageHeightPx * scale
    };
    return t;
  }
  const cropWidthPx = (crop.right - crop.left + 1) * stepX;
  const cropHeightPx = (crop.bottom - crop.top + 1) * stepY;
  const scale = cropWidthPx > 0 ? viewWidth / cropWidthPx : 1;
  const t: DisplayTransform = {
    scale: scale,
    offsetX: -crop.left * stepX * scale,
    offsetY: -crop.top * stepY * scale,
    contentHeight: cropHeightPx * scale
  };
  return t;
}

export function toPagePoint(t: DisplayTransform, screenX: number, screenY: number): PagePoint {
  const p: PagePoint = {
    x: (screenX - t.offsetX) / t.scale,
    y: (screenY - t.offsetY) / t.scale
  };
  return p;
}
