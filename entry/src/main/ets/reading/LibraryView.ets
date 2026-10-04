import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookshelfModel, BookRecord } from './BookshelfModel';
import { groupQaByChapter, QaGroup, QaRecord } from './Qa';
import { textHash } from './IndexerMath';
import { Palette, paletteOf } from './Theme';
import { PdfPageSource } from './PdfPageSource';
import { downsampleGrid } from './CropPipeline';
import { image } from '@kit.ImageKit';
import { readJsonFile, writeJsonFile } from './JsonFile';

// 书房 · 夜城风（扁平矢量 + 波普 + Lo-fi 嘻哈专辑封面）：封面墙 = 深夜里一排排亮着暖光的窗。
// 交互纪律：封面即按钮（点 = 翻开这本书的档案，继续阅读在里面）；长按 = 菜单（删除）；
// 管家住在右上角那只黑猫里；导入只剩一个「+」。没有多余的字，没有多余的按钮。

// 调色板：夜城（暗）/ 昼港（亮），由 nightMode 驱动；橙与纯黑硬阴影两模式同律

interface DraftInfo {
  anchor: number;
  end: number;
  strokes: number;
}

const ORANGE = '#FF8A2A';     // 亮橙：唯一暖光，两模式不变
const INK = '#060B12';        // 纯黑：硬阴影/橙上文字，两模式不变

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
  @State progress: Map<number, number> = new Map<number, number>();
  @State pressedKey: string = '';
  @State hoverKey: string = '';
  @State breathe: boolean = false;
  @State confirmDeleteId: number = -1;
  @StorageLink('nightMode') nightMode: boolean = true;
  @State thumbs: Map<string, boolean> = new Map<string, boolean>();
  private model: BookshelfModel = new BookshelfModel();

  aboutToAppear(): void {
    this.ensureSamplesAndLoad();
    // 黑猫呼吸：管家在打盹（迭代 -1 往复，极低调）
    this.breathe = false;
    this.getUIContext().animateTo({
      duration: 2600,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.breathe = true;
    });
  }

  private P(): Palette {
    return paletteOf(this.nightMode);
  }

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private themePath(): string {
    return this.ctx().filesDir + '/theme.json';
  }

  private loadTheme(): void {
    // theme.json 缺省 = 夜间（品牌基调）
    const obj = readJsonFile<Record<string, Object>>(this.themePath());
    if (obj !== null && typeof obj['night'] === 'boolean') {
      AppStorage.setOrCreate('nightMode', obj['night'] as boolean);
    }
  }

  private toggleTheme(): void {
    this.nightMode = !this.nightMode;
    AppStorage.setOrCreate('nightMode', this.nightMode);
    writeJsonFile(this.themePath(), JSON.stringify({ night: this.nightMode }));
  }

  private bookKeyOf(path: string): string {
    return 'b' + textHash(path);
  }

  // 封面 = 书的脸：按路径哈希取画，删除重播/排序变化都不换画
  private coverArt(id: number): Resource {
    const arts: Array<Resource> = [
      $r('app.media.cover_diner'),
      $r('app.media.cover_rooftop'),
      $r('app.media.cover_lamp'),
      $r('app.media.cover_window'),
      $r('app.media.cover_pop')
    ];
    return arts[id % arts.length];
  }

  private coverArtOf(book: BookRecord): Resource {
    // 封面 = 书的脸：用户自选优先，未选则按路径哈希稳定分配
    const idx = (book.cover === undefined)
      ? BookshelfModel.defaultCover(book.path, 5)
      : book.cover;
    return this.coverArt(idx);
  }

  // PDF 第一页缩略图（业界默认封面）：导入/播种后后台渲染一张小图，缓存到 covers/。
  // 渲染失败（加密/损坏/扫描超规格）静默回退插画封面——书永远有脸。
  private thumbPath(book: BookRecord): string {
    return `${this.ctx().filesDir}/covers/${this.bookKeyOf(book.path)}.jpg`;
  }

  private async ensureThumb(book: BookRecord): Promise<void> {
    try {
      const p = this.thumbPath(book);
      if (fs.accessSync(p)) {
        this.markThumb(book.path);
        return;
      }
      const src = new PdfPageSource();
      if (!src.open(book.path)) {
        return;
      }
      const grid = downsampleGrid(594, 840, 64);
      const pm = await src.cropPage(0, null, grid);
      src.close();
      if (pm === null) {
        return;
      }
      const packer = image.createImagePacker();
      const buf = await packer.packToData(pm, { format: 'image/jpeg', quality: 82 });
      const dir = `${this.ctx().filesDir}/covers`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const f = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, buf);
      fs.closeSync(f.fd);
      this.markThumb(book.path);
    } catch (err) {
      // 静默：插画封面顶上
    }
  }

  private markThumb(path: string): void {
    const m = new Map<string, boolean>(this.thumbs);
    m.set(path, true);
    this.thumbs = m;
  }

  private hasThumb(book: BookRecord): boolean {
    return this.thumbs.get(book.path) === true && book.cover === undefined;
  }

  private changeCover(book: BookRecord): void {
    const auto = BookshelfModel.defaultCover(book.path, 5);
    book.cover = BookshelfModel.nextCover(book.cover, auto, 5);
    this.persist();
    this.refresh();
  }

  // 书样幂等播种：文件丢了就重拷、书单里没有该路径就登记（无 marker，天然幂等）。
  // 播种归 LibraryView 管：先读盘、再补种子、立刻持久化，避免与导入互相覆盖。
  private async ensureSamplesAndLoad(): Promise<void> {
    this.loadFromDisk();
    try {
      const ctx = this.ctx();
      const booksDir = ctx.filesDir + '/books';
      if (!fs.accessSync(booksDir)) {
        fs.mkdirSync(booksDir, true);
      }
      const samples: Array<[string, string]> = [
        ['sample_textbook.pdf', '深入浅出程序设计竞赛（书样）'],
        ['sample_scan.pdf', '扫描手写件（样张）']
      ];
      let changed = false;
      for (const s of samples) {
        const path = `${booksDir}/${s[0]}`;
        if (!fs.accessSync(path)) {
          const data = await ctx.resourceManager.getRawFileContent(s[0]);
          const file = fs.openSync(path,
            fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, data.buffer as ArrayBuffer);
          fs.closeSync(file.fd);
        }
        let known = false;
        for (const b of this.model.list()) {
          if (b.path === path) {
            known = true;
            break;
          }
        }
        if (!known) {
          this.model.add(s[1], path, Date.now());
          changed = true;
        }
      }
      if (changed) {
        this.persist();
        this.refresh();
      }
    } catch (err) {
      // 书样播种失败不阻塞书架
    }
    this.loadProgress();
    this.ensureAllThumbs();
  }

  // 逐本后台补缩略图；每张完成即刷新（封面墙渐进点亮）
  private ensureAllThumbs(): void {
    for (const b of this.books) {
      this.ensureThumb(b);
    }
  }

  private readJsonObject(path: string): Record<string, Object> | null {
    return readJsonFile<Record<string, Object>>(path);
  }

  private loadFromDisk(): void {
    const arr = readJsonFile<Array<BookRecord>>(this.ctx().filesDir + '/library.json');
    if (arr !== null) {
      this.model.load(arr);
    }
    this.refresh();
  }

  // 每本书的高水位线（封面墙上的「读到 P…」）
  private loadProgress(): void {
    const map = new Map<number, number>();
    for (const b of this.books) {
      const meta = this.readJsonObject(`${this.ctx().filesDir}/progress_${this.bookKeyOf(b.path)}.json`);
      if (meta !== null && typeof meta['highWater'] === 'number') {
        map.set(b.id, meta['highWater'] as number);
      }
    }
    this.progress = map;
  }

  private persist(): void {
    writeJsonFile(this.ctx().filesDir + '/library.json', JSON.stringify(this.model.list()));
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
      // 校验拷贝完整性：空/坏文件会让 loadDocument 直接 PARSE_ERROR_FILE
      let size = 0;
      try {
        size = fs.statSync(dest).size;
      } catch (err) {
        size = 0;
      }
      if (size < 100) {
        // 退路：句柄分块读写重拷一次
        try {
          const inFd = fs.openSync(uri, fs.OpenMode.READ_ONLY);
          const outFd = fs.openSync(dest,
            fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          const buf = new ArrayBuffer(1 << 20);
          for (;;) {
            const n = fs.readSync(inFd.fd, buf);
            if (n <= 0) {
              break;
            }
            fs.writeSync(outFd.fd, buf, { length: n });
          }
          fs.closeSync(inFd);
          fs.closeSync(outFd);
          size = fs.statSync(dest).size;
        } catch (err) {
          size = 0;
        }
      }
      if (size < 100) {
        try {
          fs.unlinkSync(dest);
        } catch (err) {
          // 清理失败忽略
        }
        hilog.error(0x0000, 'LibraryView', `import copy broken (${size}B): ${uri}`);
        return;
      }
      let title = uri.substring(uri.lastIndexOf('/') + 1).replace(/\.pdf$/i, '');
      try {
        title = decodeURIComponent(title);
      } catch (err) {
        // 保留原样
      }
      // 先读盘合并，再追加，避免覆盖其它入口（如书样播种）写入的条目
      this.loadFromDisk();
      // 内容去重：与现有书同尺寸再比哈希，重复导入不生成重复书目
      const destHash = this.fileHash(dest);
      for (const b of this.model.list()) {
        try {
          if (!fs.accessSync(b.path) || fs.statSync(b.path).size !== size) {
            continue;
          }
          if (this.fileHash(b.path) === destHash) {
            fs.unlinkSync(dest);
            hilog.info(0x0000, 'LibraryView', `duplicate import skipped: ${title}`);
            return;
          }
        } catch (err) {
          continue;
        }
      }
      const rec = this.model.add(BookshelfModel.cleanTitle(title), dest, Date.now());
      this.persist();
      this.refresh();
      this.ensureThumb(rec);
    } catch (err) {
      // 用户取消选择
    }
  }

  // 内容指纹：尺寸 + 全字节 djb2（导入去重用，一次性成本可接受）
  private fileHash(path: string): string {
    const stat = fs.statSync(path);
    const buf = new ArrayBuffer(stat.size);
    const fd = fs.openSync(path, fs.OpenMode.READ_ONLY);
    fs.readSync(fd.fd, buf);
    fs.closeSync(fd);
    const b = new Uint8Array(buf);
    let h = 5381;
    for (let i = 0; i < b.length; i++) {
      h = ((h << 5) + h + b[i]) | 0;
    }
    return `${stat.size}_${h}`;
  }

  // ---------- 详情态数据 ----------
  private openDetail(book: BookRecord): void {
    this.selectedId = book.id;
    this.mode = 'detail';
    const key = this.bookKeyOf(book.path);
    this.bookQa = [];
    this.qaGroups = [];
    this.draftInfo = null;
    this.highWater = this.progress.has(book.id) ? this.progress.get(book.id)! : -1;
    try {
      const all = readJsonFile<Array<QaRecord>>(this.ctx().filesDir + '/qa.json');
      if (all !== null) {
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
    try {
      fs.unlinkSync(this.thumbPath(book));
    } catch (err) {
      // 无缩略图
    }
    this.model.remove(book.id);
    this.persist();
    this.refresh();
    // 级联清理：书文件与该书的衍生数据（进度/墨迹/草稿/OCR/章节/索引缓存），并过滤问答归档
    const key = this.bookKeyOf(book.path);
    try {
      const ctx = this.ctx();
      if (fs.accessSync(book.path)) {
        fs.unlinkSync(book.path);
      }
      const prefixes = ['progress_', 'ink_', 'draft_', 'ocr_', 'chapters_'];
      for (const pre of prefixes) {
        const p = `${ctx.filesDir}/${pre}${key}.json`;
        if (fs.accessSync(p)) {
          fs.unlinkSync(p);
        }
      }
      // 索引缓存在 filesDir/index/ 下，且向量部分是 .bin
      const indexDir = ctx.filesDir + '/index';
      for (const ext of ['.json', '.bin']) {
        const p = `${indexDir}/index_${key}${ext}`;
        if (fs.accessSync(p)) {
          fs.unlinkSync(p);
        }
      }
      const qaPath = ctx.filesDir + '/qa.json';
      const all = readJsonFile<Array<QaRecord>>(qaPath);
      if (all !== null) {
        const kept: Array<QaRecord> = [];
        for (const rec of all) {
          if (rec.bookKey !== key) {
            kept.push(rec);
          }
        }
        if (kept.length !== all.length) {
          writeJsonFile(qaPath, JSON.stringify(kept));
        }
      }
    } catch (err) {
      // 清理失败不阻塞删除（残留文件不影响功能，问答已按 bookKey 过滤不再显示）
    }
    if (this.mode === 'detail' && this.selectedId === book.id) {
      this.mode = 'shelf';
    }
  }

  private continueReading(): void {
    const b = this.detailBook();
    if (b === null) {
      return;
    }
    this.model.touch(b.id, Date.now());
    this.persist();
    this.onOpen(b.path, b.title, this.highWater >= 0 ? this.highWater : 0);
  }

  private detailBook(): BookRecord | null {
    for (const b of this.books) {
      if (b.id === this.selectedId) {
        return b;
      }
    }
    return null;
  }

  private detailStats(): string {
    let s = `问答 ${this.bookQa.length}`;
    if (this.highWater >= 0) {
      s += ` · 已读 P${this.highWater + 1}`;
    }
    if (this.draftInfo !== null && this.draftInfo.strokes > 0) {
      s += ' · 有草稿';
    }
    return s;
  }

  // 封面的按压/悬停形变：按下去落进自己的影子，悬停时从影子里浮起
  private cellScale(key: string): number {
    if (this.pressedKey === key) {
      return 0.97;
    }
    return this.hoverKey === key ? 1.03 : 1.0;
  }

  private cellShift(key: string): number {
    return this.pressedKey === key ? 4 : 0;
  }

  // ---------- 封面单元（画框 + 硬阴影 + 最少文字） ----------
  @Builder
  CoverCell(book: BookRecord, idx: number) {
    Column() {
      Stack() {
        Column()
          .width('100%')
          .aspectRatio(0.667)
          .borderRadius(12)
          .backgroundColor(INK)
          .offset({ x: 6, y: 7 })
        if (this.hasThumb(book)) {
          Image(`file://${this.thumbPath(book)}`)
            .width('100%')
            .aspectRatio(0.667)
            .borderRadius(12)
            .objectFit(ImageFit.Cover)
            .draggable(false)
        } else {
          Image(this.coverArtOf(book))
            .width('100%')
            .aspectRatio(0.667)
            .borderRadius(12)
            .draggable(false)
        }
      }
      .width('100%')
      .padding({ right: 6, bottom: 7 })

      Text(BookshelfModel.cleanTitle(book.title))
        .fontColor(this.P().text)
        .fontSize(13)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 12 })

      if (this.progress.has(book.id)) {
        Text(`读到 P${this.progress.get(book.id)! + 1}`)
          .fontColor(ORANGE)
          .fontSize(10)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .scale({ x: this.cellScale(`s${book.id}`), y: this.cellScale(`s${book.id}`) })
    .translate({ x: this.cellShift(`s${book.id}`), y: this.cellShift(`s${book.id}`) })
    .animation({ duration: 200, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      this.openDetail(book);
    })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressedKey = `s${book.id}`;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onHover((h: boolean) => {
      this.hoverKey = h ? `s${book.id}` : '';
    })
    .bindContextMenu(this.cellMenu(book), ResponseType.LongPress)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 26 }))
      .animation({ duration: 420, curve: Curve.Friction, delay: 60 + idx * 55 }))
  }

  @Builder
  cellMenu(book: BookRecord) {
    Menu() {
      MenuItem({ content: '换封面' })
        .contentFontColor(this.P().text)
        .onClick(() => {
          this.changeCover(book);
        })
      MenuItem({ content: this.confirmDeleteId === book.id ? '再点一次，确认删除' : '删除这本书' })
        .contentFontColor(this.confirmDeleteId === book.id ? ORANGE : this.P().text)
        .onClick(() => {
          if (this.confirmDeleteId === book.id) {
            this.confirmDeleteId = -1;
            this.removeBook(book);
          } else {
            this.confirmDeleteId = book.id;
          }
        })
    }
    .backgroundColor(this.P().panelMenu)
    .borderRadius(14)
    .shadow({ radius: 0, color: INK, offsetX: 4, offsetY: 5 })
  }

  // ---------- 书脊（详情态左列，用真封面缩略） ----------
  @Builder
  SpineItem(book: BookRecord) {
    Column() {
      Image(this.coverArtOf(book))
        .width(62)
        .aspectRatio(0.667)
        .borderRadius(6)
        .draggable(false)
        .opacity(this.selectedId === book.id ? 1.0 : 0.7)
        .border(this.selectedId === book.id ? { width: 2, color: ORANGE } : { width: 0, color: ORANGE })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .animation({ duration: 180, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      this.openDetail(book);
    })
    .bindContextMenu(this.cellMenu(book), ResponseType.LongPress)
  }

  // 书越少列越少：封面越大，画廊感越强；书多了回归密排封面墙
  private shelfCols(): number {
    const n = this.books.length;
    if (n <= 3) {
      return 3;
    }
    if (n <= 8) {
      return 4;
    }
    return 5;
  }

  private cellWidthPct(): string {
    const cols = this.shelfCols();
    if (cols === 3) {
      return '29%';
    }
    if (cols === 4) {
      return '21.5%';
    }
    return '17%';
  }

  // ---------- 书柜封面墙 ----------
  @Builder
  ShelfMode() {
    Column() {
      Row() {
        Text('书房')
          .fontColor(this.P().text)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text(this.nightMode ? '日' : '夜')
          .fontColor(this.nightMode ? this.P().dim : this.P().text)
          .fontSize(15)
          .width(42)
          .height(42)
          .textAlign(TextAlign.Center)
          .borderRadius(13)
          .backgroundColor(this.P().panel)
          .border({ width: 1, color: this.P().hair })
          .margin({ right: 14 })
          .onClick(() => {
            this.toggleTheme();
          })
        Column() {
          Image($r('app.media.cat'))
            .width(44)
            .height(44)
            .scale({ x: this.breathe ? 1.06 : 0.96, y: this.breathe ? 1.06 : 0.96 })
            .animation({
              duration: 2600,
              curve: Curve.EaseInOut,
              iterations: -1,
              playMode: PlayMode.Alternate
            })
          Text('管家')
            .fontColor(this.P().dim)
            .fontSize(10)
            .margin({ top: 2 })
        }
        .margin({ right: 20 })
        .onClick(() => {
          this.onOpenStudy();
        })

        Text('+')
          .fontColor(ORANGE)
          .fontSize(26)
          .fontWeight(FontWeight.Medium)
          .width(46)
          .height(46)
          .textAlign(TextAlign.Center)
          .borderRadius(14)
          .backgroundColor(this.P().panel)
          .shadow({ radius: 0, color: INK, offsetX: 3, offsetY: 4 })
          .onClick(() => {
            this.importPdf();
          })
      }
      .width('100%')
      .padding({ left: 28, right: 28, top: 20, bottom: 14 })

      if (this.books.length === 0) {
        Column() {
          Image($r('app.media.empty_shelf'))
            .width('58%')
            .aspectRatio(1.42)
            .borderRadius(16)
            .shadow({ radius: 0, color: INK, offsetX: 8, offsetY: 10 })
          Text('书房还空着')
            .fontColor(this.P().text)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 34 })
          Text('点这里，或右上角的 +，导入第一本 PDF')
            .fontColor(this.P().dim)
            .fontSize(13)
            .margin({ top: 10 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.importPdf();
        })
      } else {
        Scroll() {
          Column() {
            // 画廊墙：Flex 居中换行——末行不满格时也保持水平居中（GridRow 会靠左）
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
              ForEach(this.books, (b: BookRecord, idx: number) => {
                Column() {
                  this.CoverCell(b, idx)
                }
                .width(this.cellWidthPct())
                .padding({ left: 12, right: 12, bottom: 30 })
              }, (b: BookRecord) => `bk_${b.id}`)
            }
            .width('100%')
            .padding({ top: 10, bottom: 40 })
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.P().bg)
  }

  // ---------- 这本书的全部（书脊 + 按章归档，条条回跳） ----------
  @Builder
  DetailMode() {
    Row() {
      Column() {
        Row() {
          Text('←')
            .fontColor(this.P().text)
            .fontSize(18)
            .width(38)
            .height(38)
            .textAlign(TextAlign.Center)
            .borderRadius(12)
            .backgroundColor(this.P().panel)
            .shadow({ radius: 0, color: INK, offsetX: 2, offsetY: 3 })
            .onClick(() => {
              this.mode = 'shelf';
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 16, bottom: 10 })
        Scroll() {
          Column({ space: 16 }) {
            ForEach(this.books, (b: BookRecord) => {
              this.SpineItem(b)
            }, (b: BookRecord) => `sp_${b.id}`)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding({ bottom: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width(126)
      .height('100%')
      .backgroundColor(this.P().bgDeep)

      if (this.detailBook() === null) {
        Column() {
          Text('选一本书')
            .fontColor(this.P().faint)
            .fontSize(13)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text(BookshelfModel.cleanTitle(this.detailBook()!.title))
            .fontColor(this.P().text)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.detailStats())
            .fontColor(this.P().dim)
            .fontSize(12)
            .margin({ top: 8 })

          Row() {
            Text(this.highWater >= 0 ? `继续阅读 P${this.highWater + 1}` : '开始阅读')
              .fontColor(INK)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
          }
          .padding({ left: 30, right: 30, top: 14, bottom: 14 })
          .borderRadius(12)
          .backgroundColor(ORANGE)
          .shadow({ radius: 0, color: INK, offsetX: 4, offsetY: 5 })
          .margin({ top: 20 })
          .scale({ x: this.pressedKey === 'go' ? 0.97 : 1.0, y: this.pressedKey === 'go' ? 0.97 : 1.0 })
          .animation({ duration: 160, curve: Curve.FastOutSlowIn })
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              this.pressedKey = 'go';
            } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
              this.pressedKey = '';
            }
          })
          .onClick(() => {
            this.continueReading();
          })

          if (this.draftInfo !== null && this.draftInfo.strokes > 0) {
            Row() {
              Column() {
                Text('草稿')
                  .fontColor(this.P().faint)
                  .fontSize(10)
                  .letterSpacing(2)
                Text(`范围 P${this.draftInfo.anchor + 1}–P${this.draftInfo.end + 1} · ${this.draftInfo.strokes} 笔`)
                  .fontColor(this.P().text)
                  .fontSize(13)
                  .margin({ top: 5 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('→')
                .fontColor(ORANGE)
                .fontSize(16)
            }
            .width('100%')
            .padding(16)
            .borderRadius(12)
            .backgroundColor(this.P().panel)
            .margin({ top: 24 })
            .onClick(() => {
              const b = this.detailBook();
              if (b !== null && this.draftInfo !== null) {
                this.onOpen(b.path, b.title, this.draftInfo.anchor);
              }
            })
          }

          Text('笔记与对话')
            .fontColor(this.P().faint)
            .fontSize(11)
            .letterSpacing(2)
            .margin({ top: 28 })

          if (this.qaGroups.length === 0) {
            Column() {
              Row() {
                Image($r('app.media.cat'))
                  .width(64)
                  .height(64)
                Text('阅读时圈选提问，会按章沉淀在这里')
                  .fontColor(this.P().faint)
                  .fontSize(12)
                  .margin({ left: 14 })
                  .layoutWeight(1)
              }
              .width('82%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
            Column() {
              ForEach(this.qaGroups, (g: QaGroup) => {
                Text(`${g.chapterTitle} · ${g.items.length}`)
                  .fontColor(ORANGE)
                  .fontSize(11)
                  .margin({ top: 14, bottom: 2 })
                ForEach(g.items, (rec: QaRecord) => {
                  Row() {
                    Text(rec.question)
                      .fontColor(this.P().text)
                      .fontSize(13)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text(`P${rec.pageIndex + 1}`)
                      .fontColor(this.P().faint)
                      .fontSize(11)
                      .margin({ left: 14 })
                  }
                  .width('100%')
                  .padding({ top: 11, bottom: 11 })
                  .border({ width: { bottom: 0.8 }, color: { bottom: this.P().hair } })
                  .onClick(() => {
                    const b = this.detailBook();
                    if (b !== null) {
                      this.onOpen(b.path, b.title, rec.pageIndex);
                    }
                  })
                }, (rec: QaRecord) => `qa_${rec.createdAt}`)
              }, (g: QaGroup) => `grp_${g.chapterTitle}`)
              Row()
                .height(30)
                .width(1)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .padding({ left: 30, right: 36, top: 26, bottom: 6 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.P().bg)
  }

  build() {
    if (this.mode === 'detail') {
      this.DetailMode();
    } else {
      this.ShelfMode();
    }
  }
}
