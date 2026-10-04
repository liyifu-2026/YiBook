import { describe, it, expect } from '@ohos/hypium';
import { strokesToJson, strokesFromJson } from '../main/ets/reading/InkPersistence';
import { InkStore, InkStroke } from '../main/ets/reading/InkStore';
import { InkPoint } from '../main/ets/reading/GestureMath';

function stroke(pageIndex: number, xs: Array<number>, isAi: boolean, regularized: boolean,
  shapeString: string): InkStroke {
  const points: Array<InkPoint> = [];
  for (let i = 0; i < xs.length; i += 2) {
    const p: InkPoint = { x: xs[i], y: xs[i + 1] };
    points.push(p);
  }
  const s: InkStroke = {
    pageIndex: pageIndex,
    pagePoints: points,
    isAi: isAi,
    regularized: regularized,
    shapeString: shapeString
  };
  return s;
}

export default function inkPersistenceTest() {
  describe('inkPersistence', () => {
    it('round-trips strokes through json losslessly', 0, () => {
      const strokes: Array<InkStroke> = [
        stroke(3, [10.5, 20, 30.25, 40], false, false, ''),
        stroke(0, [1, 2, 3, 4, 5, 6], true, true, 'M0 0 L10 10')
      ];
      const json = strokesToJson(strokes);
      const back = strokesFromJson(json);
      expect(back.length).assertEqual(2);
      expect(back[0].pageIndex).assertEqual(3);
      expect(back[0].pagePoints.length).assertEqual(2);
      expect(back[0].pagePoints[1].x).assertEqual(30.25);
      expect(back[1].regularized).assertTrue();
      expect(back[1].shapeString).assertEqual('M0 0 L10 10');
      expect(back[1].isAi).assertTrue();
    });

    it('tolerates empty json', 0, () => {
      expect(strokesFromJson(strokesToJson([])).length).assertEqual(0);
    });

    it('removeLast pops only the newest stroke of that page', 0, () => {
      const store = new InkStore();
      store.add(stroke(1, [1, 1], false, false, ''));
      store.add(stroke(1, [2, 2], false, false, ''));
      store.add(stroke(2, [3, 3], false, false, ''));
      store.removeLast(1);
      expect(store.strokesOf(1).length).assertEqual(1);
      expect(store.strokesOf(1)[0].pagePoints[0].x).assertEqual(1);
      expect(store.strokesOf(2).length).assertEqual(1);
      store.removeLast(9);
      expect(store.count()).assertEqual(2);
    });
  });
}
