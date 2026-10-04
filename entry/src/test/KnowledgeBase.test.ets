import { describe, it, expect } from '@ohos/hypium';
import { KnowledgeBase, BookIndexEntry } from '../main/ets/search/KnowledgeBase';
import { LexicalIndex } from '../main/ets/search/LexicalIndex';
import { IndexedChunk } from '../main/ets/search/SearchOrchestrator';

function entry(key: string, title: string, id0: number, text: string): BookIndexEntry {
  const lex = new LexicalIndex();
  lex.add(id0, text);
  const c: IndexedChunk = { id: id0, sourceLine: `P${id0}`, text: text, vec: [], pageIndex: id0, charStart: 0, charEnd: 10 };
  const chunks: Array<IndexedChunk> = [c];
  const e: BookIndexEntry = { bookKey: key, bookTitle: title, lexical: lex, chunks: chunks };
  return e;
}

export default function knowledgeBaseTest() {
  describe('knowledgeBase', () => {
    it('cross-book search interleaves hits from every matching book', 0, () => {
      const kb = new KnowledgeBase();
      kb.register(entry('a', '信号与系统', 1, '傅里叶变换是频率分析工具'));
      kb.register(entry('b', '数字信号处理', 7, '傅里叶变换的离散形式DFT'));
      kb.register(entry('c', '概率论', 9, '期望与方差'));
      const hits = kb.searchCrossBook('傅里叶变换', 1);
      expect(hits.length).assertEqual(2);
      expect(hits[0].bookTitle === '信号与系统' || hits[0].bookTitle === '数字信号处理').assertTrue();
      const titles: Array<string> = [hits[0].bookTitle, hits[1].bookTitle];
      expect(titles[0] !== titles[1]).assertTrue();
    });

    it('unregister removes a book from the knowledge base', 0, () => {
      const kb = new KnowledgeBase();
      kb.register(entry('a', '信号', 1, '傅里叶变换'));
      kb.unregister('a');
      expect(kb.searchCrossBook('傅里叶变换', 3).length).assertEqual(0);
    });
  });
}
