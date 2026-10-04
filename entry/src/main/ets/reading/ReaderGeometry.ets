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

export function transformForCrop(pageWidth: number, pageHeight: number, crop: BBox | null,
  viewWidth: number): DisplayTransform {
  if (crop === null) {
    const scale = pageWidth > 0 ? viewWidth / pageWidth : 1;
    const t: DisplayTransform = {
      scale: scale,
      offsetX: 0,
      offsetY: 0,
      contentHeight: pageHeight * scale
    };
    return t;
  }
  const cropWidth = crop.right - crop.left + 1;
  const cropHeight = crop.bottom - crop.top + 1;
  const scale = viewWidth / cropWidth;
  const t: DisplayTransform = {
    scale: scale,
    offsetX: -crop.left * scale,
    offsetY: -crop.top * scale,
    contentHeight: cropHeight * scale
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
