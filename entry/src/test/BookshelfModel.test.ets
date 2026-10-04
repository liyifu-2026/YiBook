import { describe, it, expect } from '@ohos/hypium';
import { BookshelfModel } from '../main/ets/book/BookshelfModel';

export default function bookshelfModelTest() {
  describe('bookshelfModel', () => {
    it('adds books and lists most-recently-opened first', 0, () => {
      const shelf = new BookshelfModel();
      const a = shelf.add('信号与系统', '/books/a.pdf', 100);
      const b = shelf.add('概率论', '/books/b.pdf', 200);
      expect(shelf.count()).assertEqual(2);
      expect(shelf.list()[0].title).assertEqual('概率论');
      shelf.touch(a.id, 300);
      expect(shelf.list()[0].title).assertEqual('信号与系统');
      expect(shelf.list()[1].title).assertEqual('概率论');
      expect(b.lastOpenedAt).assertEqual(0);
    });

    it('remove drops only the chosen book', 0, () => {
      const shelf = new BookshelfModel();
      const a = shelf.add('A', '/a.pdf', 1);
      shelf.add('B', '/b.pdf', 2);
      shelf.remove(a.id);
      expect(shelf.count()).assertEqual(1);
      expect(shelf.list()[0].title).assertEqual('B');
    });

    it('cleanTitle strips download-site watermarks but keeps author parens', 0, () => {
      expect(BookshelfModel.cleanTitle('C++数据结构与算法 (Adam Drozdek) (z-library.sk, 1lib.sk, z-lib.sk)'))
        .assertEqual('C++数据结构与算法（Adam Drozdek）');
      expect(BookshelfModel.cleanTitle('深入浅出程序设计竞赛（书样）'))
        .assertEqual('深入浅出程序设计竞赛（书样）');
      expect(BookshelfModel.cleanTitle('算法导论 (.pdf)')).assertEqual('算法导论');
      expect(BookshelfModel.cleanTitle('Introduction to Algorithms (Third Edition)'))
        .assertEqual('Introduction to Algorithms (Third Edition)');
    });

    it('cover selection is stable by default and cycles on demand', 0, () => {
      const a = BookshelfModel.defaultCover('/books/a.pdf', 5);
      const b = BookshelfModel.defaultCover('/books/a.pdf', 5);
      expect(a).assertEqual(b);
      expect(a >= 0 && a < 5).assertEqual(true);
      expect(BookshelfModel.nextCover(undefined, a, 5)).assertEqual((a + 1) % 5);
      expect(BookshelfModel.nextCover(4, 0, 5)).assertEqual(0);
    });
  });
}
