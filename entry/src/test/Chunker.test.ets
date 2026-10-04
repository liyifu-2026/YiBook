import { describe, it, expect } from '@ohos/hypium';
import { chunkText } from '../main/ets/reading/Chunker';

export default function chunkerTest() {
  describe('chunker', () => {
    it('merges small paragraphs into one chunk within target', 0, () => {
      const p1 = 'a'.repeat(100);
      const p2 = 'b'.repeat(100);
      const text = `${p1}\n\n${p2}`;
      const chunks = chunkText(text, 250, 400);
      expect(chunks.length).assertEqual(1);
      expect(chunks[0].charStart).assertEqual(0);
      expect(chunks[0].charEnd).assertEqual(202);
      expect(chunks[0].text === text.substring(0, 202)).assertTrue();
    });

    it('starts a new chunk when target exceeded', 0, () => {
      const text = `${'a'.repeat(100)}\n${'b'.repeat(100)}`;
      const chunks = chunkText(text, 120, 400);
      expect(chunks.length).assertEqual(2);
      expect(chunks[0].charEnd).assertEqual(100);
      expect(chunks[1].charStart).assertEqual(101);
    });

    it('hard-splits a single paragraph over the max', 0, () => {
      const text = 'x'.repeat(300);
      const chunks = chunkText(text, 120, 150);
      expect(chunks.length).assertEqual(2);
      expect(chunks[0].charEnd).assertEqual(150);
      expect(chunks[1].charStart).assertEqual(150);
      expect(chunks[1].charEnd).assertEqual(300);
    });

    it('char offsets always match the source text', 0, () => {
      const text = `${'第一段'.repeat(50)}\n中间行\n${'第三段'.repeat(50)}`;
      const chunks = chunkText(text, 200, 400);
      for (const c of chunks) {
        expect(c.text === text.substring(c.charStart, c.charEnd)).assertTrue();
      }
      expect(chunks.length > 0).assertTrue();
    });

    it('empty text yields no chunks', 0, () => {
      expect(chunkText('', 200, 400).length).assertEqual(0);
    });
  });
}
