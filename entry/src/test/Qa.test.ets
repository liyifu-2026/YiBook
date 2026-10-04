import { describe, it, expect } from '@ohos/hypium';
import { groupQaByChapter, QaRecord } from '../main/ets/reading/Qa';

function rec(page: number, chapter: string): QaRecord {
  const r: QaRecord = {
    bookKey: 'b1',
    bookTitle: '信号与系统',
    bookPath: '/books/a.pdf',
    pageIndex: page,
    anchorY: 0,
    chapterTitle: chapter,
    question: 'q',
    answer: 'a',
    createdAt: Date.now()
  };
  return r;
}

export default function qaTest() {
  describe('qa', () => {
    it('groups by chapter ordered by first page, items by page', 0, () => {
      const groups = groupQaByChapter([
        rec(13, '卷二'), rec(2, '卷一'), rec(4, '卷一'), rec(20, '卷三'), rec(3, '卷一')
      ]);
      expect(groups.length).assertEqual(3);
      expect(groups[0].chapterTitle).assertEqual('卷一');
      expect(groups[0].items.length).assertEqual(3);
      expect(groups[0].items[0].pageIndex).assertEqual(2);
      expect(groups[0].items[2].pageIndex).assertEqual(4);
      expect(groups[1].chapterTitle).assertEqual('卷二');
      expect(groups[2].chapterTitle).assertEqual('卷三');
    });

    it('empty input yields empty groups', 0, () => {
      expect(groupQaByChapter([]).length).assertEqual(0);
    });
  });
}
