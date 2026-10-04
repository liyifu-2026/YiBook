import { describe, it, expect } from '@ohos/hypium';
import { bubbleOnQuestion, markAnswerReady, markSettled, projectToViewport,
  anchorScrollY, foldBubbles, bubblesFromQa, BubblePhase, QuestionBubble } from '../main/ets/ink/BubbleModel';

interface QaLite {
  bookKey: string;
  pageIndex: number;
  anchorY: number;
}

export default function bubbleModelTest() {
  describe('bubbleModel', () => {
    it('question is born thinking, then done, then settled — never backwards', 0, () => {
      let b = bubbleOnQuestion(1, 3, 120);
      expect(b.phase).assertEqual(BubblePhase.Thinking);
      b = markSettled(b);
      expect(b.phase).assertEqual(BubblePhase.Thinking);
      b = markAnswerReady(b);
      expect(b.phase).assertEqual(BubblePhase.Done);
      b = markSettled(b);
      expect(b.phase).assertEqual(BubblePhase.Settled);
      b = markAnswerReady(b);
      expect(b.phase).assertEqual(BubblePhase.Settled);
    });

    it('projects anchor into viewport and pins when scrolled away', 0, () => {
      const anchor = anchorScrollY(1000, 800, 200, 50); // 页顶1000 + 锚点1/4处 = 1200
      expect(anchor).assertEqual(1200);
      expect(projectToViewport(anchor, 1000, 600)).assertEqual(200);
      expect(projectToViewport(anchor, 1200, 600)).assertEqual(0);
      expect(projectToViewport(anchor, 900, 600)).assertEqual(300);
      expect(projectToViewport(anchor, 500, 600)).assertEqual(-1);
      expect(projectToViewport(anchor, 2000, 600)).assertEqual(-1);
    });

    it('shows newest bubbles and folds the rest into +N', 0, () => {
      const bubbles: Array<QuestionBubble> = [];
      for (let i = 1; i <= 7; i++) {
        bubbles.push(bubbleOnQuestion(i, 0, i * 10));
      }
      const folded = foldBubbles(bubbles, 5);
      expect(folded.shown.length).assertEqual(5);
      expect(folded.extraCount).assertEqual(2);
      expect(folded.shown[4].id).assertEqual(7);
      expect(folded.shown[0].id).assertEqual(3);
      const all = foldBubbles(bubbles, 5);
      expect(all.shown.length).assertEqual(5);
    });

    it('restores settled bubbles from this book\'s qa records only', 0, () => {
      const recs: Array<QaLite> = [
        { bookKey: 'b1', pageIndex: 4, anchorY: 120 },
        { bookKey: 'b2', pageIndex: 9, anchorY: 60 },
        { bookKey: 'b1', pageIndex: 12, anchorY: 300 }
      ];
      const restored = bubblesFromQa(recs, 'b1', 1000000);
      expect(restored.length).assertEqual(2);
      expect(restored[0].pageIndex).assertEqual(4);
      expect(restored[0].anchorY).assertEqual(120);
      expect(restored[0].phase).assertEqual(BubblePhase.Settled);
      expect(restored[0].id).assertEqual(1000000);
      expect(restored[1].id).assertEqual(1000001);
    });

    it('restores nothing from empty records', 0, () => {
      expect(bubblesFromQa([], 'b1', 1000000).length).assertEqual(0);
    });
  });
}
