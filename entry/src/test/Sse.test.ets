import { describe, it, expect } from '@ohos/hypium';
import { extractSseEvents, Utf8Feeder } from '../main/ets/reading/Sse';

export default function sseTest() {
  describe('sse', () => {
    it('extracts complete events and keeps the partial tail', 0, () => {
      const r = extractSseEvents('data: {"a":1}\n\ndata: {"b":2}\n\ndata: {"c"');
      expect(r.events.length).assertEqual(2);
      expect(r.events[0]).assertEqual('{"a":1}');
      expect(r.events[1]).assertEqual('{"b":2}');
      expect(r.rest).assertEqual('data: {"c"');
    });

    it('normalizes CRLF and passes DONE through', 0, () => {
      const r = extractSseEvents('data: x\r\n\r\ndata: [DONE]\r\n\r\n');
      expect(r.events.length).assertEqual(2);
      expect(r.events[0]).assertEqual('x');
      expect(r.events[1]).assertEqual('[DONE]');
      expect(r.rest).assertEqual('');
    });

    it('joins multi data lines and ignores comments', 0, () => {
      const r = extractSseEvents(': ping\ndata: a\ndata: b\n\ndata: c\n\n');
      expect(r.events.length).assertEqual(2);
      expect(r.events[0]).assertEqual('a\nb');
      expect(r.events[1]).assertEqual('c');
    });

    it('utf8 feeder holds incomplete multi-byte chars across feeds', 0, () => {
      const feeder = new Utf8Feeder();
      const bytes = new Uint8Array([0xE4, 0xBD, 0xA0, 0xE5, 0xA5]); // 你 的前2字节
      const first = feeder.feed(bytes);
      expect(first).assertEqual('你');
      const second = feeder.feed(new Uint8Array([0xBD]));
      expect(second).assertEqual('好');
      expect(feeder.flush()).assertEqual('');
    });
  });
}
