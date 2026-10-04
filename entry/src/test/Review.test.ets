import { describe, it, expect } from '@ohos/hypium';
import { newCard, reviewCard } from '../main/ets/reading/Review';

const DAY = 86400000;

export default function reviewTest() {
  describe('review', () => {
    it('new card schedules one day after first success', 0, () => {
      let c = newCard(0);
      expect(c.ease).assertEqual(2.5);
      expect(c.reps).assertEqual(0);
      c = reviewCard(c, 4, 0);
      expect(c.reps).assertEqual(1);
      expect(c.intervalDays).assertEqual(1);
      expect(c.dueAt).assertEqual(DAY);
    });

    it('second success goes to six days, third multiplies by ease', 0, () => {
      let c = newCard(0);
      c = reviewCard(c, 4, 0);
      c = reviewCard(c, 4, DAY);
      expect(c.intervalDays).assertEqual(6);
      c = reviewCard(c, 4, 7 * DAY);
      expect(c.intervalDays).assertEqual(15);
    });

    it('failure resets reps and eases down', 0, () => {
      let c = newCard(0);
      c = reviewCard(c, 4, 0);
      c = reviewCard(c, 4, DAY);
      c = reviewCard(c, 1, 7 * DAY);
      expect(c.reps).assertEqual(0);
      expect(c.intervalDays).assertEqual(1);
      expect(c.ease).assertClose(2.3, 0.000001);
    });

    it('ease never drops below 1.3 and quality 5 eases up', 0, () => {
      let c = newCard(0);
      for (let i = 0; i < 8; i++) {
        c = reviewCard(c, 1, i * DAY);
      }
      expect(c.ease).assertEqual(1.3);
      let e = newCard(0);
      e = reviewCard(e, 5, 0);
      expect(e.ease).assertClose(2.6, 0.000001);
    });
  });
}
