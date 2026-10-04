import { InkStroke } from './InkStore';
import { InkPoint } from './GestureMath';

// 墨迹持久化：笔迹 ↔ JSON（点扁平化为 [x0,y0,x1,y1,…]），纯函数可测。

export function strokesToJson(strokes: Array<InkStroke>): string {
  const arr: Array<Record<string, Object>> = [];
  for (const s of strokes) {
    const flat: Array<number> = [];
    for (const p of s.pagePoints) {
      flat.push(p.x);
      flat.push(p.y);
    }
    const o: Record<string, Object> = {
      'pageIndex': s.pageIndex,
      'points': flat,
      'isAi': s.isAi,
      'regularized': s.regularized,
      'shapeString': s.shapeString
    };
    if (s.capScale !== undefined) {
      o['capScale'] = s.capScale;
      o['capOffX'] = s.capOffX as Object;
      o['capOffY'] = s.capOffY as Object;
    }
    arr.push(o);
  }
  return JSON.stringify(arr);
}

export function strokesFromJson(json: string): Array<InkStroke> {
  const out: Array<InkStroke> = [];
  const arr = JSON.parse(json) as Array<Record<string, Object>>;
  for (const o of arr) {
    const flat = o['points'] as Array<number>;
    const points: Array<InkPoint> = [];
    for (let i = 0; i + 1 < flat.length; i += 2) {
      const p: InkPoint = { x: flat[i], y: flat[i + 1] };
      points.push(p);
    }
    const s: InkStroke = {
      pageIndex: o['pageIndex'] as number,
      pagePoints: points,
      isAi: o['isAi'] as boolean,
      regularized: o['regularized'] as boolean,
      shapeString: o['shapeString'] as string
    };
    if (o['capScale'] !== undefined) {
      s.capScale = o['capScale'] as number;
      s.capOffX = o['capOffX'] as number;
      s.capOffY = o['capOffY'] as number;
    }
    out.push(s);
  }
  return out;
}
