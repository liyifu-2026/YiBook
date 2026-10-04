import { BBox } from './CropMath';

// 手势词表（设计定稿）：只有 AI 笔迹的「圈」和「框」触发提问，其余一律忽略。
// shapeType 取自系统 Pen Kit InstantShapeGenerator 的 ShapeInfo：
// 2=圆(椭圆) 6=矩形，0=识别失败 1=直线 3=折线，12=五角星……
export enum GestureKind {
  Ignore = 0,
  Question = 1
}

export interface InkPoint {
  x: number;
  y: number;
}

export function strokeBBox(points: Array<InkPoint>): BBox | null {
  if (points.length === 0) {
    return null;
  }
  let left = points[0].x;
  let top = points[0].y;
  let right = points[0].x;
  let bottom = points[0].y;
  for (let i = 1; i < points.length; i++) {
    const p = points[i];
    if (p.x < left) {
      left = p.x;
    }
    if (p.y < top) {
      top = p.y;
    }
    if (p.x > right) {
      right = p.x;
    }
    if (p.y > bottom) {
      bottom = p.y;
    }
  }
  const box: BBox = { left: left, top: top, right: right, bottom: bottom };
  return box;
}

export function mapShapeToGesture(shapeType: number, bbox: BBox | null): GestureKind {
  if (bbox === null) {
    return GestureKind.Ignore;
  }
  if (shapeType === 2 || shapeType === 6) {
    return GestureKind.Question;
  }
  return GestureKind.Ignore;
}
