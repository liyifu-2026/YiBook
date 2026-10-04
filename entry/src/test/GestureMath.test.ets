import { describe, it, expect } from '@ohos/hypium';
import { strokeBBox, mapShapeToGesture, GestureKind, InkPoint } from '../main/ets/reading/GestureMath';

function pts(coords: Array<number>): Array<InkPoint> {
  const out: Array<InkPoint> = [];
  for (let i = 0; i < coords.length; i += 2) {
    const p: InkPoint = { x: coords[i], y: coords[i + 1] };
    out.push(p);
  }
  return out;
}

export default function gestureMathTest() {
  describe('gestureMath', () => {
    it('stroke bbox spans the drawn region', 0, () => {
      const b = strokeBBox(pts([10, 20, 40, 15, 30, 50]));
      expect(b !== null).assertTrue();
      if (b === null) {
        return;
      }
      expect(b.left).assertEqual(10);
      expect(b.top).assertEqual(15);
      expect(b.right).assertEqual(40);
      expect(b.bottom).assertEqual(50);
    });

    it('empty stroke has no bbox', 0, () => {
      expect(strokeBBox([])).assertNull();
    });

    it('only circle and rectangle trigger the question gesture', 0, () => {
      const b = strokeBBox(pts([0, 0, 10, 10]));
      const region = (b === null) ? null : b;
      expect(mapShapeToGesture(2, region)).assertEqual(GestureKind.Question);
      expect(mapShapeToGesture(6, region)).assertEqual(GestureKind.Question);
      expect(mapShapeToGesture(0, region)).assertEqual(GestureKind.Ignore);
      expect(mapShapeToGesture(1, region)).assertEqual(GestureKind.Ignore);
      expect(mapShapeToGesture(3, region)).assertEqual(GestureKind.Ignore);
      expect(mapShapeToGesture(12, region)).assertEqual(GestureKind.Ignore);
      expect(mapShapeToGesture(2, null)).assertEqual(GestureKind.Ignore);
    });
  });
}
