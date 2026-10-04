import { LexicalIndex } from './LexicalIndex';
import { IndexedChunk } from './SearchOrchestrator';

// 统一知识库（愿景「打穿书本间隔」）：本会话内打开过的书在此注册，
// 位置检索时跨书查询，出处标明书名。隐私边界见决策 #14。

export interface BookIndexEntry {
  bookKey: string;
  bookTitle: string;
  lexical: LexicalIndex;
  chunks: Array<IndexedChunk>;
}

export interface CrossHit {
  bookKey: string;
  bookTitle: string;
  chunk: IndexedChunk;
}

export class KnowledgeBase {
  private static inst: KnowledgeBase | null = null;

  static shared(): KnowledgeBase {
    if (KnowledgeBase.inst === null) {
      KnowledgeBase.inst = new KnowledgeBase();
    }
    return KnowledgeBase.inst;
  }

  private registry: Map<string, BookIndexEntry> = new Map();

  register(entry: BookIndexEntry): void {
    this.registry.set(entry.bookKey, entry);
  }

  unregister(bookKey: string): void {
    this.registry.delete(bookKey);
  }

  registeredCount(): number {
    return this.registry.size;
  }

  // 每本书各取前 perBook 条命中，按轮转交错合并（公平跨书，不偏向单本）
  searchCrossBook(query: string, perBook: number): Array<CrossHit> {
    const perBookHits: Array<Array<CrossHit>> = [];
    for (const entry of this.registry.values()) {
      const ids = entry.lexical.search(query, perBook);
      const hits: Array<CrossHit> = [];
      for (const id of ids) {
        for (const c of entry.chunks) {
          if (c.id === id) {
            const hit: CrossHit = {
              bookKey: entry.bookKey,
              bookTitle: entry.bookTitle,
              chunk: c
            };
            hits.push(hit);
            break;
          }
        }
      }
      perBookHits.push(hits);
    }
    const out: Array<CrossHit> = [];
    let more = true;
    for (let round = 0; more; round++) {
      more = false;
      for (const hits of perBookHits) {
        if (round < hits.length) {
          out.push(hits[round]);
          more = true;
        }
      }
    }
    return out;
  }
}
