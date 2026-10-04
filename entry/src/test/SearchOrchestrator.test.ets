import { describe, it, expect } from '@ohos/hypium';
import { selectBlocks, filterRead, IndexedChunk } from '../main/ets/search/SearchOrchestrator';

function chunk(id: number, sourceLine: string, text: string, vec: Array<number>): IndexedChunk {
  const c: IndexedChunk = { id: id, sourceLine: sourceLine, text: text, vec: vec, pageIndex: id, charStart: 0, charEnd: 10 };
  return c;
}

export default function searchOrchestratorTest() {
  describe('searchOrchestrator', () => {
    it('fuses both channels, dedups, diversifies, caps budget', 0, () => {
      const chunks: Array<IndexedChunk> = [
        chunk(1, 'P10', 'aaaaaaaaaa', [1, 0]),
        chunk(2, 'P11', 'bbbbbbbbbb', [0.98, 0.01]),
        chunk(3, 'P12', 'cccccccccc', [0, 1]),
        chunk(4, 'P13', 'dddddddddd', [0.5, 0.5])
      ];
      const sel = selectBlocks([1, 0], [1, 2], [2, 3], chunks, 0.4, 25);
      expect(sel.blocks.length).assertEqual(2);
      expect(sel.blocks[0].id).assertEqual(1);
      expect(sel.blocks[0].text).assertEqual('aaaaaaaaaa');
      expect(sel.blocks[0].sourceLine).assertEqual('P10');
      expect(sel.blocks[1].sourceLine).assertEqual('P12');
    });

    it('empty query vector takes fused order without MMR', 0, () => {
      const chunks: Array<IndexedChunk> = [
        chunk(1, 'P10', 'aaaaaaaaaa', [1, 0]),
        chunk(2, 'P11', 'bbbbbbbbbb', [0, 1])
      ];
      const sel = selectBlocks([], [2, 1], [], chunks, 0.6, 999);
      expect(sel.blocks.length).assertEqual(2);
      expect(sel.blocks[0].id).assertEqual(1);
      expect(sel.blocks[0].sourceLine).assertEqual('P11');
      expect(sel.blocks[1].text).assertEqual('aaaaaaaaaa');
    });

    it('progress filter keeps only chunks within read pages unless whole-book mode', 0, () => {
      const chunks: Array<IndexedChunk> = [
        chunk(1, 'P1', 'aaa', [1, 0]),
        chunk(5, 'P5', 'bbb', [0, 1]),
        chunk(9, 'P9', 'ccc', [1, 1])
      ];
      expect(filterRead(chunks, 5, false).length).assertEqual(2);
      expect(filterRead(chunks, 5, true).length).assertEqual(3);
      expect(filterRead(chunks, 5, false)[1].id).assertEqual(5);
    });
  });
}
