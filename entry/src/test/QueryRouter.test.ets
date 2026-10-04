import { describe, it, expect } from '@ohos/hypium';
import { routeQuery, QueryRoute } from '../main/ets/reading/QueryRouter';

export default function queryRouterTest() {
  describe('queryRouter', () => {
    it('location questions always retrieve across the book', 0, () => {
      expect(routeQuery(true, '书里哪里还讲到傅里叶', false)).assertEqual(QueryRoute.LocateInBook);
      expect(routeQuery(false, '哪些地方定义了它', true)).assertEqual(QueryRoute.LocateInBook);
    });

    it('follow-up with deixis continues the previous turn', 0, () => {
      expect(routeQuery(false, '那这个呢', true)).assertEqual(QueryRoute.FollowUp);
      expect(routeQuery(false, '为什么', true)).assertEqual(QueryRoute.FollowUp);
    });

    it('short circled questions skip retrieval', 0, () => {
      expect(routeQuery(true, '这是什么意思', false)).assertEqual(QueryRoute.CircledLookup);
    });

    it('everything else is general', 0, () => {
      expect(routeQuery(false, '请详细解释动态规划的状态设计方法', false)).assertEqual(QueryRoute.General);
      expect(routeQuery(true, '这个和下一节的递推有什么联系与区别', false)).assertEqual(QueryRoute.General);
    });
  });
}
