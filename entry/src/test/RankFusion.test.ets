import { describe, it, expect } from '@ohos/hypium';
import { rrfFuse, mmrSelect } from '../main/ets/search/RankFusion';

export default function rankFusionTest() {
  describe('rankFusion', () => {
    it('RRF puts items hit by both channels on top', 0, () => {
      const fused = rrfFuse([[1, 2, 3], [2, 4]], 60);
      expect(fused.length).assertEqual(4);
      expect(fused[0]).assertEqual(2);
      expect(fused[3]).assertEqual(3);
    });

    it('MMR trades relevance for diversity', 0, () => {
      const query: Array<number> = [1, 0];
      const candidates: Array<Array<number>> = [
        [0.9, 0.05],       // 0：最相关
        [0.85, 0.1],       // 1：0 的近重复
        [0.2, 0.9]         // 2：相关但与 0 正交成分大
      ];
      const picked = mmrSelect(query, candidates, 0.4, 2);
      expect(picked.length).assertEqual(2);
      expect(picked[0]).assertEqual(0);
      expect(picked[1]).assertEqual(2);
    });

    it('MMR with lambda 1 degrades to pure relevance', 0, () => {
      const query: Array<number> = [1, 0];
      const candidates: Array<Array<number>> = [
        [0.9, 0.1],
        [0.8, 0.6],
        [0.7, 0]
      ];
      const picked = mmrSelect(query, candidates, 1, 2);
      expect(picked[0]).assertEqual(2);
      expect(picked[1]).assertEqual(0);
    });

    it('dimension mismatch never produces NaN selection', 0, () => {
      // 查询 2 维、候选 3 维：不可比时相似度按 0 处理，MMR 不返回 -1、不抛错
      const query: Array<number> = [1, 0];
      const candidates: Array<Array<number>> = [
        [1, 0, 0],
        [0, 1, 0]
      ];
      const picked = mmrSelect(query, candidates, 0.6, 2);
      expect(picked.length).assertEqual(2);
      expect(picked[0]).assertEqual(0);
      expect(picked[1]).assertEqual(1);
    });
  });
}
