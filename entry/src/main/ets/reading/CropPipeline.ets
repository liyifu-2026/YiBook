import { BBox, ParityCrop } from './CropMath';
import { PagePoint } from './ReaderGeometry';

export interface SampleGrid {
  cols: number;
  rows: number;
  stepX: number;
  stepY: number;
}

export function downsampleGrid(pixelWidth: number, pixelHeight: number,
  maxSamplesPerAxis: number): SampleGrid {
  const stepX = Math.ceil(pixelWidth / maxSamplesPerAxis);
  const stepY = Math.ceil(pixelHeight / maxSamplesPerAxis);
  const grid: SampleGrid = {
    cols: Math.ceil(pixelWidth / stepX),
    rows: Math.ceil(pixelHeight / stepY),
    stepX: stepX,
    stepY: stepY
  };
  return grid;
}

// 约定：首页 = index 0 = 偶数簇
export function parityCropFor(pageIndex: number, parity: ParityCrop): BBox | null {
  return pageIndex % 2 === 0 ? parity.even : parity.odd;
}

export function sampleToPagePoint(sampleX: number, sampleY: number, grid: SampleGrid,
  pageWidth: number, pageHeight: number): PagePoint {
  const p: PagePoint = {
    x: Math.min((sampleX + 0.5) * grid.stepX, pageWidth),
    y: Math.min((sampleY + 0.5) * grid.stepY, pageHeight)
  };
  return p;
}

export interface PixelRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

// T1：手势框（采样栅格坐标）→ 像素区域，外扩 padRatio 并钳制在页内
export function regionForBBox(bbox: BBox, grid: SampleGrid, pagePixelW: number,
  pagePixelH: number, padRatio: number): PixelRect {
  const rx = (bbox.right - bbox.left + 1) * grid.stepX;
  const ry = (bbox.bottom - bbox.top + 1) * grid.stepY;
  const padX = rx * padRatio;
  const padY = ry * padRatio;
  let x = bbox.left * grid.stepX - padX;
  let y = bbox.top * grid.stepY - padY;
  let w = rx + 2 * padX;
  let h = ry + 2 * padY;
  if (x < 0) {
    x = 0;
  }
  if (y < 0) {
    y = 0;
  }
  if (x + w > pagePixelW) {
    w = pagePixelW - x;
  }
  if (y + h > pagePixelH) {
    h = pagePixelH - y;
  }
  const r: PixelRect = {
    x: Math.max(0, Math.round(x)),
    y: Math.max(0, Math.round(y)),
    width: Math.max(1, Math.round(w)),
    height: Math.max(1, Math.round(h))
  };
  return r;
}

// T0 补全：原生 PDF 无字符坐标，用圈选区在页面中的百分比位置作聚焦提示，
// 让模型在整页文字层内只解释该区域。
export function regionHint(bbox: BBox, grid: SampleGrid, pagePixelW: number,
  pagePixelH: number): string {
  const y0 = Math.round(bbox.top * grid.stepY / pagePixelH * 100);
  const y1 = Math.round((bbox.bottom + 1) * grid.stepY / pagePixelH * 100);
  const x0 = Math.round(bbox.left * grid.stepX / pagePixelW * 100);
  const x1 = Math.round((bbox.right + 1) * grid.stepX / pagePixelW * 100);
  return `页面纵向约${y0}%-${y1}%、横向约${x0}%-${x1}%的区域`;
}
