import { describe, it, expect } from '@ohos/hypium';
import { OcrTexts } from '../main/ets/reading/OcrTexts';

export default function ocrTextsTest() {
  describe('ocrTexts', () => {
    it('stores and reads per-page text', 0, () => {
      const o = new OcrTexts();
      expect(o.has(3)).assertFalse();
      expect(o.get(3)).assertEqual('');
      o.set(3, '傅里叶变换的内容');
      o.set(7, '动态规划');
      expect(o.has(3)).assertTrue();
      expect(o.get(3)).assertEqual('傅里叶变换的内容');
      expect(o.count()).assertEqual(2);
    });

    it('missingPages lists un-ocred pages within the cap', 0, () => {
      const o = new OcrTexts();
      o.set(0, 'a');
      o.set(2, 'c');
      const missing = o.missingPages(10, 5);
      expect(missing.length).assertEqual(3);
      expect(missing[0]).assertEqual(1);
      expect(missing[1]).assertEqual(3);
      expect(missing[2]).assertEqual(4);
    });

    it('round-trips through records for persistence', 0, () => {
      const o = new OcrTexts();
      o.set(1, '第一页');
      o.set(5, '第五页');
      const o2 = new OcrTexts();
      o2.load(o.all());
      expect(o2.count()).assertEqual(2);
      expect(o2.get(5)).assertEqual('第五页');
      const all = o2.all();
      expect(all[0].page).assertEqual(1);
      expect(all[1].page).assertEqual(5);
    });

    it('set overwrites the same page', 0, () => {
      const o = new OcrTexts();
      o.set(2, '旧');
      o.set(2, '新');
      expect(o.get(2)).assertEqual('新');
      expect(o.count()).assertEqual(1);
    });
  });
}
