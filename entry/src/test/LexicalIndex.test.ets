import { describe, it, expect } from '@ohos/hypium';
import { tokenize, LexicalIndex } from '../main/ets/search/LexicalIndex';

export default function lexicalIndexTest() {
  describe('lexicalIndex', () => {
    it('tokenizes cjk bigrams and latin words', 0, () => {
      const tokens = tokenize('傅里叶变换 Fourier');
      expect(tokens[0]).assertEqual('傅里');
      expect(tokens[1]).assertEqual('里叶');
      expect(tokens[3]).assertEqual('变换');
      expect(tokens[4]).assertEqual('fourier');
      const single = tokenize('排序');
      expect(single.length).assertEqual(1);
      expect(single[0]).assertEqual('排序');
    });

    it('bm25 ranks matching docs first, higher tf higher', 0, () => {
      const index = new LexicalIndex();
      index.add(1, '傅里叶变换是信号处理的重要工具');
      index.add(2, '快速排序是最快的通用排序算法');
      index.add(3, '傅里叶变换在傅里叶变换中的应用举例');
      const hits = index.search('傅里叶变换', 3);
      expect(hits.length).assertEqual(2);
      expect(hits[0]).assertEqual(3);
      expect(hits[1]).assertEqual(1);
    });

    it('search respects topK', 0, () => {
      const index = new LexicalIndex();
      index.add(1, '动态规划入门');
      index.add(2, '动态规划进阶');
      index.add(3, '图论基础');
      const hits = index.search('动态规划', 1);
      expect(hits.length).assertEqual(1);
    });
  });
}
