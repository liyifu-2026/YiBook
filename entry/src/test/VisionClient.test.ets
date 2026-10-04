import { describe, it, expect } from '@ohos/hypium';
import { buildVisionMessages } from '../main/ets/reading/VisionClient';

export default function visionClientTest() {
  describe('visionClient', () => {
    it('builds system text and user multimodal parts with data url', 0, () => {
      const msgs = buildVisionMessages('你是OCR引擎', '转录这段内容', 'QUJD', 'image/jpeg');
      expect(msgs.length).assertEqual(2);
      expect(msgs[0].role).assertEqual('system');
      expect(msgs[1].role).assertEqual('user');
      expect(msgs[1].content.length).assertEqual(2);
      expect(msgs[1].content[0].text).assertEqual('转录这段内容');
      expect(msgs[1].content[1].imageUrl).assertEqual('data:image/jpeg;base64,QUJD');
    });
  });
}
