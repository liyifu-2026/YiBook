// T3 全书 OCR 的页文本仓：按页缓存视觉模型转录结果（纯逻辑，持久化在设备层）。
// 一次 OCR，终身受用——重开书零费用。

export interface OcrRecord {
  page: number;
  text: string;
}

export class OcrTexts {
  private byPage: Map<number, string> = new Map();

  load(records: Array<OcrRecord>): void {
    this.byPage = new Map();
    for (const r of records) {
      this.byPage.set(r.page, r.text);
    }
  }

  set(page: number, text: string): void {
    this.byPage.set(page, text);
  }

  get(page: number): string {
    const v = this.byPage.get(page);
    return v === undefined ? '' : v;
  }

  has(page: number): boolean {
    return this.byPage.has(page);
  }

  count(): number {
    return this.byPage.size;
  }

  all(): Array<OcrRecord> {
    const out: Array<OcrRecord> = [];
    const pages: Array<number> = [];
    for (const p of this.byPage.keys()) {
      pages.push(p);
    }
    pages.sort((a, b) => a - b);
    for (const p of pages) {
      const r: OcrRecord = { page: p, text: this.byPage.get(p) as string };
      out.push(r);
    }
    return out;
  }

  // 尚未 OCR 的页（0 起，上限 maxPages）
  missingPages(total: number, maxPages: number): Array<number> {
    const cap = Math.min(total, maxPages);
    const out: Array<number> = [];
    for (let i = 0; i < cap; i++) {
      if (!this.byPage.has(i)) {
        out.push(i);
      }
    }
    return out;
  }
}
