// 书架数据模型（书房 M5 的数据层）：导入的书 + 最近打开排序。纯逻辑，持久化在设备层。
import { textHash } from './IndexerMath';

// 未打开过的书在「最近打开排序」里的补偿偏移：新导入的书排在打开过的书之后，
// 又不至于永远沉底（一年内的打开记录仍会让位于新导入）。
const NEVER_OPENED_OFFSET = 31536000000;

export interface BookRecord {
  id: number;
  title: string;
  path: string;
  addedAt: number;
  lastOpenedAt: number; // 0 = 从未打开
  cover?: number; // 用户自选封面（0-4）；缺省 = 按路径哈希自动分配
}

export class BookshelfModel {
  private books: Array<BookRecord> = [];
  private nextId: number = 1;

  load(books: Array<BookRecord>): void {
    this.books = books;
    let max = 0;
    for (const b of this.books) {
      if (b.id > max) {
        max = b.id;
      }
    }
    this.nextId = max + 1;
  }

  list(): Array<BookRecord> {
    const out = this.books.slice();
    out.sort((a, b) => {
      const ka = a.lastOpenedAt > 0 ? a.lastOpenedAt : a.addedAt - NEVER_OPENED_OFFSET;
      const kb = b.lastOpenedAt > 0 ? b.lastOpenedAt : b.addedAt - NEVER_OPENED_OFFSET;
      return kb - ka;
    });
    return out;
  }

  add(title: string, path: string, now: number): BookRecord {
    const rec: BookRecord = {
      id: this.nextId,
      title: title,
      path: path,
      addedAt: now,
      lastOpenedAt: 0
    };
    this.nextId++;
    this.books.push(rec);
    return rec;
  }

  touch(id: number, now: number): void {
    for (const b of this.books) {
      if (b.id === id) {
        b.lastOpenedAt = now;
        return;
      }
    }
  }

  remove(id: number): void {
    const out: Array<BookRecord> = [];
    for (const b of this.books) {
      if (b.id !== id) {
        out.push(b);
      }
    }
    this.books = out;
  }

  count(): number {
    return this.books.length;
  }

  // 默认封面：按路径哈希稳定分配（同一本书永远同一张画，与增删/重播顺序无关）
  static defaultCover(path: string, poolSize: number): number {
    const h = parseInt(textHash(path).substring(0, 8), 16);
    return Math.abs(h) % poolSize;
  }

  // 换封面：在封面池内循环推进一格（未选过 = 从自动分配的当前张推进）
  static nextCover(current: number | undefined, autoCover: number, poolSize: number): number {
    const cur = (current === undefined) ? autoCover : current;
    return ((cur + 1) % poolSize + poolSize) % poolSize;
  }

  // 展示用标题清洗：剥离下载站/格式水印括号段（z-library.sk、.pdf 等），保留书名与作者段；
  // 中文书名统一全角括号并去掉括号前冗余空格。
  static cleanTitle(raw: string): string {
    const watermark = /(lib\.sk|z-lib|libgen|bookfi|booksc|\.pdf|\.epub|\.mobi|\.azw|ebook|annotated|scanned|ocr)/i;
    let t = raw.replace(/[（(][^()（）]*[)）]/g, (seg: string): string => watermark.test(seg) ? ' ' : seg);
    t = t.replace(/\s{2,}/g, ' ').trim();
    t = t.replace(/[-–—、,，]\s*$/, '').trim();
    if (/[\u4e00-\u9fff]/.test(t)) {
      t = t.replace(/\s*[(]\s*/g, '（').replace(/\s*[)]\s*/g, '）');
      t = t.replace(/\s{2,}/g, ' ').trim();
    }
    return t === '' ? raw.trim() : t;
  }
}
