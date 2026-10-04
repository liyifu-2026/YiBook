import { describe, it, expect } from '@ohos/hypium';
import { bookOutlineSummary, chapterExcerpt } from '../main/ets/ai/ContextSummary';
import { Chapter } from '../main/ets/book/ChapterModel';

function ch(id: number, title: string, first: number, last: number): Chapter {
  const c: Chapter = { id: id, title: title, firstPage: first, lastPage: last, manual: false };
  return c;
}

export default function contextSummaryTest() {
  describe('contextSummary', () => {
    it('outline lists chapters with start pages', 0, () => {
      const chapters: Array<Chapter> = [ch(0, '卷一', 0, 9), ch(1, '卷二', 10, 24)];
      const s = bookOutlineSummary(chapters, 500);
      expect(s.indexOf('全书共2章') >= 0).assertTrue();
      expect(s.indexOf('卷一(P1)') >= 0).assertTrue();
      expect(s.indexOf('卷二(P11)') >= 0).assertTrue();
    });

    it('outline drops trailing chapters to fit budget', 0, () => {
      const chapters: Array<Chapter> = [
        ch(0, '第一章很长很长很长', 0, 9),
        ch(1, '第二章很长很长很长', 10, 19),
        ch(2, '第三章很长很长很长', 20, 29)
      ];
      const s = bookOutlineSummary(chapters, 40);
      expect(s.indexOf('等3章') >= 0).assertTrue();
      expect(s.length <= 60).assertTrue();
    });

    it('chapter excerpt carries range and head text', 0, () => {
      const s = chapterExcerpt(2, 8, '本章从傅里叶级数讲起，先回顾三角函数。', 20);
      expect(s.indexOf('本章P3-P9') >= 0).assertTrue();
      expect(s.indexOf('本章从傅里叶级数讲起') >= 0).assertTrue();
      const capped = chapterExcerpt(2, 8, '字'.repeat(100), 20);
      expect(capped.indexOf('字'.repeat(20)) >= 0).assertTrue();
      expect(capped.indexOf('字'.repeat(21)) < 0).assertTrue();
    });
  });
}
