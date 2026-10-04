import { describe, it, expect } from '@ohos/hypium';
import { ReviewQueue } from '../main/ets/reading/ReviewQueue';

const DAY = 86400000;

export default function reviewQueueTest() {
  describe('reviewQueue', () => {
    it('new quiz is due immediately; grading pushes dueAt out', 0, () => {
      const q = new ReviewQueue();
      q.addQuiz('k1', '信号与系统', 5, '什么是傅里叶变换', '把信号分解为频率成分', 0);
      expect(q.dueCount(0)).assertEqual(1);
      q.grade('k1', 4, 0);
      expect(q.dueCount(0)).assertEqual(0);
      expect(q.due(1 * DAY).length).assertEqual(1);
    });

    it('due list orders by dueAt ascending', 0, () => {
      const q = new ReviewQueue();
      q.addQuiz('a', '书A', 1, 'q1', 'ans1', 0);
      q.addQuiz('b', '书B', 2, 'q2', 'ans2', 0);
      q.grade('b', 4, 0); // b 到明天，a 仍在今天
      const due = q.due(0);
      expect(due.length).assertEqual(1);
      expect(due[0].id).assertEqual('a');
    });

    it('round-trips through json for persistence', 0, () => {
      const q = new ReviewQueue();
      q.addQuiz('k', '书', 3, 'q', 'a', 0);
      const q2 = new ReviewQueue();
      q2.load(q.all());
      expect(q2.count()).assertEqual(1);
      q2.grade('k', 5, DAY);
      expect(q2.dueCount(DAY + 1)).assertEqual(0);
    });
  });
}
