import { describe, it, expect } from '@ohos/hypium';
import { chaptersFromOutline, chapterAt, split, mergeNext, rename, moveBoundary } from '../main/ets/book/ChapterModel';
import { OutlineMarker, Chapter } from '../main/ets/core/DocModel';

function marker(title: string, page: number): OutlineMarker {
  const m: OutlineMarker = { title: title, page: page };
  return m;
}

export default function chapterModelTest() {
  describe('chapterModel', () => {
    it('auto-splits from outline markers into contiguous chapters', 0, () => {
      const markers: Array<OutlineMarker> = [marker('卷一', 0), marker('卷二', 10), marker('卷三', 25)];
      const chapters = chaptersFromOutline(markers, 40);
      expect(chapters.length).assertEqual(3);
      expect(chapters[0].title).assertEqual('卷一');
      expect(chapters[0].firstPage).assertEqual(0);
      expect(chapters[0].lastPage).assertEqual(9);
      expect(chapters[1].title).assertEqual('卷二');
      expect(chapters[1].firstPage).assertEqual(10);
      expect(chapters[1].lastPage).assertEqual(24);
      expect(chapters[2].lastPage).assertEqual(39);
      expect(chapters[2].manual).assertFalse();
    });

    it('empty outline yields the whole book as one chapter', 0, () => {
      const chapters = chaptersFromOutline([], 40);
      expect(chapters.length).assertEqual(1);
      expect(chapters[0].firstPage).assertEqual(0);
      expect(chapters[0].lastPage).assertEqual(39);
    });

    it('pages before the first marker form a front-matter chapter', 0, () => {
      const markers: Array<OutlineMarker> = [marker('第一章', 5)];
      const chapters = chaptersFromOutline(markers, 20);
      expect(chapters.length).assertEqual(2);
      expect(chapters[0].title).assertEqual('卷首');
      expect(chapters[0].lastPage).assertEqual(4);
      expect(chapters[1].firstPage).assertEqual(5);
    });

    it('markers beyond the last page are dropped', 0, () => {
      const markers: Array<OutlineMarker> = [marker('卷一', 0), marker('幽灵章', 99)];
      const chapters = chaptersFromOutline(markers, 40);
      expect(chapters.length).assertEqual(1);
      expect(chapters[0].title).assertEqual('卷一');
    });

    it('per-page garbage outline falls back to the whole book', 0, () => {
      const markers: Array<OutlineMarker> = [];
      for (let p = 0; p < 327; p++) {
        markers.push(marker(`部分${p}_1`, p));
      }
      const chapters = chaptersFromOutline(markers, 327);
      expect(chapters.length).assertEqual(1);
      expect(chapters[0].title).assertEqual('全书');
      expect(chapters[0].lastPage).assertEqual(326);
    });

    it('locates the chapter containing a page', 0, () => {
      const chapters = chaptersFromOutline([marker('卷一', 0), marker('卷二', 10)], 40);
      expect(chapterAt(chapters, 0)).assertEqual(0);
      expect(chapterAt(chapters, 9)).assertEqual(0);
      expect(chapterAt(chapters, 10)).assertEqual(1);
      expect(chapterAt(chapters, 40)).assertEqual(-1);
    });

    it('clamp splits a chapter into two at the page', 0, () => {
      const chapters = chaptersFromOutline([marker('卷一', 0), marker('卷二', 10)], 40);
      const after = split(chapters, 1, 15);
      expect(after.length).assertEqual(3);
      expect(after[1].title).assertEqual('卷二');
      expect(after[1].lastPage).assertEqual(14);
      expect(after[2].title).assertEqual('未命名');
      expect(after[2].firstPage).assertEqual(15);
      expect(after[2].lastPage).assertEqual(39);
      expect(after[2].manual).assertTrue();
    });

    it('merge joins a chapter with the next one', 0, () => {
      const chapters = chaptersFromOutline([marker('卷一', 0), marker('卷二', 10), marker('卷三', 25)], 40);
      const after = mergeNext(chapters, 1);
      expect(after.length).assertEqual(2);
      expect(after[1].title).assertEqual('卷二');
      expect(after[1].firstPage).assertEqual(10);
      expect(after[1].lastPage).assertEqual(39);
      const last = mergeNext(chapters, 2);
      expect(last.length).assertEqual(3);
    });

    it('moveBoundary shifts the seam between neighbors and clamps', 0, () => {
      const chapters = chaptersFromOutline([marker('卷一', 0), marker('卷二', 10), marker('卷三', 25)], 40);
      const after = moveBoundary(chapters, 2, 20);
      expect(after[1].lastPage).assertEqual(19);
      expect(after[2].firstPage).assertEqual(20);
      const clamped = moveBoundary(chapters, 2, 0);
      expect(clamped[1].lastPage).assertEqual(10);
      expect(clamped[2].firstPage).assertEqual(11);
    });

    it('rename only changes the title', 0, () => {
      const chapters = chaptersFromOutline([marker('卷一', 0)], 40);
      const after = rename(chapters, 0, '信号与系统');
      expect(after[0].title).assertEqual('信号与系统');
      expect(after[0].firstPage).assertEqual(0);
    });
  });
}
