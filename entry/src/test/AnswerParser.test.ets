import { describe, it, expect } from '@ohos/hypium';
import { parseAnswer } from '../main/ets/ai/AnswerParser';

export default function answerParserTest() {
  describe('answerParser', () => {
    it('keeps valid citation ids in order and drops hallucinated ones', 0, () => {
      const p = parseAnswer('傅里叶变换把时域变频域[^2]，且满足线性[^1]。见[^9]。', [1, 2]);
      expect(p.refs.length).assertEqual(2);
      expect(p.refs[0]).assertEqual(2);
      expect(p.refs[1]).assertEqual(1);
      expect(p.text.indexOf('[^9]') < 0).assertTrue();
      expect(p.text.indexOf('[^2]') >= 0).assertTrue();
    });

    it('deduplicates repeated citations and tolerates no refs', 0, () => {
      const p = parseAnswer('重复[^1]再引[^1]，无引用结尾', [1]);
      expect(p.refs.length).assertEqual(1);
      expect(p.refs[0]).assertEqual(1);
      const empty = parseAnswer('没有任何引用', [1, 2]);
      expect(empty.refs.length).assertEqual(0);
      expect(empty.text.indexOf('没有任何引用') >= 0).assertTrue();
    });
  });
}
