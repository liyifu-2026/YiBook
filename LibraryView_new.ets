import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BookshelfModel, BookRecord } from './BookshelfModel';
import { groupQaByChapter, QaGroup, QaRecord } from './Qa';
import { textHash } from './IndexerMath';

// 书房双态（设计文档「书本外」）：书柜封面墙 ⇄ 书列 + 本书内容（按章归档，条条回跳）。

interface DraftInfo {
  anchor: number;
  end: number;
  strokes: number;
}

const COVER_SHADES: Array<string> = ['#2f2f37', '#3a3442', '#2a3440', '#403a2f', '#33403a'];

@Component
export struct LibraryView {
  onOpen: (path: string, title: string, page: number) => void = (_p: string, _t: string, _pg: number) => {
  };
  onOpenStudy: () => void = () => {
  };
  @State books: Array<BookRecord> = [];
  @State mode: string = 'shelf'; // shelf | detail
  @State selectedId: number = -1;
  @State bookQa: Array<QaRecord> = [];
  @State qaGroups: Array<QaGroup> = [];
  @State draftInfo: DraftInfo | null = null;
  @State highWater: number = -1;
  private model: BookshelfModel = new BookshelfModel();

  aboutToAppear(): void {
    this.loadLibrary();
  }

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private bookKeyOf(path: string): string {
    return 'b' + textHash(path);
  }

  private readJsonObject(path: string): Record<string, Object> | null {
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      const stat = fs.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      const fd = fs.openSync(path, fs.OpenMode.READ_ONLY);
      fs.readSync(fd.fd, buf);
      fs.closeSync(fd);
      const decoder = util.TextDecoder.create('utf-8');
      return JSON.parse(decoder.decodeToString(new Uint8Array(buf))) as Record<string, Object>;
    } catch (err) {
      return null;
    }
  }

  private loadLibrary(): void {
    try {
      const path = this.ctx().filesDir + '/library.json';
      if (fs.accessSync(path)) {
        const stat = fs.statSync(path);
        const buf = new ArrayBuffer(stat.size);
        const fd = fs.openSync(path, fs.OpenMode.READ_ONLY);
        fs.readSync(fd.fd, buf);
        fs.closeSync(fd);
        const decoder = util.TextDecoder.create('utf-8');
        const arr = JSON.parse(decoder.decodeToString(new Uint8Array(buf))) as Array<BookRecord>;
        this.model.load(arr);
      }
    } catch (err) {
      // 首次启动无书单
    }
    this.refresh();
  }

  private persist(): void {
    try {
      const json = JSON.stringify(this.model.list());
      const tmp = this.ctx().filesDir + '/library.json.tmp';
      const fd = fs.openSync(tmp,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(fd.fd, json);
      fs.closeSync(fd);
      fs.renameSync(tmp, this.ctx().filesDir + '/library.json');
    } catch (err) {
      // 保存失败不阻塞
    }
  }

  private refresh(): void {
    this.books = this.model.list();
  }

  private async importPdf(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.fileSuffixFilters = ['.pdf'];
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const dir = this.ctx().filesDir + '/books';
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const dest = `${dir}/book_${Date.now()}.pdf`;
      const srcFd = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFile(srcFd.fd, dest);
      fs.closeSync(srcFd);
      let title = uri.substring(uri.lastIndexOf('/') + 1).replace(/\.pdf$/i, '');
      try {
        title = decodeURIComponent(title);
      } catch (err) {
        // 保留原样
      }
      this.model.add(title, dest, Date.now());
      this.persist();
      this.refresh();
    } catch (err) {
      // 用户取消选择
    }
  }

  // ---------- 详情态数据 ----------
  private openDetail(book: BookRecord): void {
    this.selectedId = book.id;
    this.mode = 'detail';
    const key = this.bookKeyOf(book.path);
    this.bookQa = [];
    this.qaGroups = [];
    this.draftInfo = null;
    this.highWater = -1;
    try {
      const qaPath = this.ctx().filesDir + '/qa.json';
      if (fs.accessSync(qaPath)) {
        const stat = fs.statSync(qaPath);
        const buf = new ArrayBuffer(stat.size);
        const fd = fs.openSync(qaPath, fs.OpenMode.READ_ONLY);
        fs.readSync(fd.fd, buf);
        fs.closeSync(fd);
        const decoder = util.TextDecoder.create('utf-8');
        const all = JSON.parse(decoder.decodeToString(new Uint8Array(buf))) as Array<QaRecord>;
        for (const rec of all) {
          if (rec.bookKey === key) {
            this.bookQa.push(rec);
          }
        }
        this.qaGroups = groupQaByChapter(this.bookQa);
      }
    } catch (err) {
      // 无问答
    }
    try {
      const meta = this.readJsonObject(`${this.ctx().filesDir}/draft_${key}.json`);
      if (meta !== null) {
        const strokesStr = meta['strokes'] as string;
        let strokes = 0;
        try {
          strokes = (JSON.parse(strokesStr) as Array<Object>).length;
        } catch (err) {
          strokes = 0;
        }
        const info: DraftInfo = {
          anchor: meta['anchor'] as number,
          end: meta['end'] as number,
          strokes: strokes
        };
        this.draftInfo = info;
      }
    } catch (err) {
      // 无草稿
    }
    try {
      const meta = this.readJsonObject(`${this.ctx().filesDir}/progress_${key}.json`);
      if (meta !== null) {
        this.highWater = meta['highWater'] as number;
      }
    } catch (err) {
      // 无进度
    }
  }

  private removeBook(book: BookRecord): void {
    this.model.remove(book.id);
    this.persist();
    this.refresh();
  }

  // ---------- 书柜封面 ----------
  @Builder
  Cover(book: BookRecord, large: boolean) {
    Column() {
      Column() {
        Text(book.title)
          .fontColor('#EEEEEE')
          .fontSize(large ? 13 : 11)
          .maxLines(3)
          .textAlign(TextAlign.Center)
          .width('100%')
        Text('亦书')
          .fontColor('#666666')
          .fontSize(9)
          .margin({ top: 6 })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .width(large ? 96 : 74)
    .height(large ? 136 : 106)
    .borderRadius({ topLeft: 4, topRight: 8, bottomRight: 8, bottomLeft: 4 })
    .backgroundColor(COVER_SHADES[book.id % COVER_SHADES.length])
    .border({
      width: { left: 3 },
      color: { left: '#111111' }
    })
    .shadow({ radius: 6, color: 'rgba(0,0,0,0.5)', offsetY: 3 })
  }

  // ---------- 书柜态 ----------
  @Builder
  ShelfMode() {
    Column() {
      Row() {
        Text('书房')
          .fontColor('#EEEEEE')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button('管家')
          .fontSize(13)
          .height(34)
          .backgroundColor('#3A3A3A')
          .margin({ right: 6 })
          .onClick(() => {
            this.onOpenStudy();
          })
        Button('导入 PDF')
          .fontSize(14)
          .height(34)
          .backgroundColor('#7C5CFF')
          .onClick(() => {
            this.importPdf();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.books.length === 0) {
        Column() {
          Text('书架空空')
            .fontColor('#888888')
            .fontSize(15)
          Text('导入一本教材 PDF 开始连续阅读')
            .fontColor('#666666')
            .fontSize(12)
            .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            GridRow({ columns: 4, gutter: 12 }) {
              ForEach(this.books, (b: BookRecord) => {
                GridCol() {
                  Column() {
                    Column() {
       
