// PdfReaderView：走系统 PdfView 的阅读视图（清晰 + 流畅 + 官方坐标换算）。
//
// 关键坐标设计（第二项需求的根本）：
//   墨迹**不用** ScrollParam 换算 —— 实测 registerScrollListener 几乎不触发（offY 恒为 0），
//   靠它墨迹就会钉在屏幕上、不跟页面走。改用 SDK 官方的成对换算：
//     viewPointToPDFPoint(pageIndex, viewPoint)  屏幕 -> 页内 PDF 点
//     pdfPointToViewPoint(pageIndex, pdfPoint)   页内 PDF 点 -> 屏幕
//   这两条自带缩放/滚动/旋转/页间距的全部处理，我们只负责换算，不自己维护偏移量。
//
//   墨迹坐标统一为「**页内 PDF 点按页累加**」的文档空间：
//     docX = 页内 x（PDF 点）
//     docY = pageIndex * pageHpt + 页内 y（PDF 点）
//   因为 setPageSpacing(0,0) 让页缝为 0，第 k 页的底边在文档空间里就**正好是**第 k+1 页的顶边，
//   所以一笔跨页时坐标天然连续 —— 这就是「不同页码拼接无间隙、连续书写不断笔」的底层保证。
//
// 书写自动滚屏：为了写字时页面不乱跑，落笔会 enablePageDrag(false) 冻住拖动；
// 于是笔写到屏幕边缘就需要**我们主动滚动**（否则笔迹会在边缘断掉）。
// onTick 里按笔尖进入边缘区的深浅滚动页面，并把滚动后的新位置继续追加进当前笔画。
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { fileExists, readTextFile, writeJsonFile } from '../core/JsonFile';
import { textHash } from '../book/IndexerMath';
import { updateHighWater } from '../book/ReadingProgress';
import { DocLayout, DocPoint, DocStroke, INK_PLAIN, INK_AI,
  pageIndexAt, pagesOfStroke, boxOfStroke, findHitStroke, simplify,
  strokesToJson, strokesFromJson } from '../ink/DocInk';

// 运行时的 TouchObject 带 sourceTool（编译器声明滞后，与 ink/PageInkCanvas 同法）
interface ProbeTouch {
  x: number;
  y: number;
  sourceTool?: SourceTool;
}

// ⚠️ 必须用 SDK 符号 SourceTool.Pen，**不要写字面量**：
// 该枚举是 Unknown=0, Finger=1, Pen=2, MOUSE, TOUCHPAD, JOYSTICK。
// 曾把 Pen 误写成 1（那其实是 Finger）→ 笔被拒（写不了）+ 手指被当笔（误画）。
const PEN_TOOL: SourceTool = SourceTool.Pen;

const PEN_PLAIN = 0;
const PEN_AI = 1;
const PEN_ERASER = 2;

// 夜城风：全应用只有黑白墨色，唯一彩色属于 AI（液态彩）
const INK_COLOR = '#101E33';
const AI_COLOR = '#4C9AFF';
const NIGHT = '#101E33';

const WIDTHS: Array<number> = [2, 4, 7];
const RAIL_W = 64;          // 左右黑边余区宽度（vp）

// 书写自动滚屏参数（px）
const EDGE_ZONE = 140;
const EDGE_MAX_STEP = 26;
const TICK_MS = 33;

// 一页在屏幕上的线性映射：view = (ox + localX * sx, oy + localY * sy)
interface PageMap {
  ox: number;
  oy: number;
}

@Entry
@Component
export struct PdfReaderView {
  @Prop pdfPath: string = '';
  @Prop bookTitle: string = '';
  @Prop initialPage: number = -1;
  @Prop debugCrossPage: boolean = false;

  // 文档布局：**单位是 PDF 点**，gap 恒为 0（setPageSpacing(0,0) 保证页缝为 0）
  private docLayout: DocLayout = { pageW: 0, pageH: 0, gap: 0, count: 0 };
  private viewW: number = 0;
  private viewH: number = 0;
  private pdfW: number = 0;     // 整卷按宽度铺满后的像素宽（来自 ScrollParam）

  @State pageNo: number = 0;
  @State highWater: number = 0;
  @State loaded: boolean = false;
  @State note: string = '准备中…';

  // ---- 墨迹 ----
  private strokes: Array<DocStroke> = [];
  private live: Array<DocPoint> = [];
  private livePen: number = PEN_PLAIN;
  private strokeSeq: number = 0;
  private inkKey: string = 'book';
  private dirty: boolean = false;
  private saveTimer: number = -1;
  private injected: boolean = false;

  // ---- 书写自动滚屏 / 跟随重绘 ----
  private tickTimer: number = -1;
  private lastTouchMs: number = 0;
  private lastPenX: number = 0;
  private lastPenY: number = 0;
  private fingerY: number = -1;   // 手指上一次的 y（用于自己累计滚动偏移）

  // ---- 笔设置（顶部栏驱动）----
  @State pen: number = PEN_PLAIN;
  @State penWidthIdx: number = 1;

  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    this.inkKey = 'b' + textHash(this.pdfPath);
    this.loadInk();
    this.open();
  }

  aboutToDisappear(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    this.stopTicker();
    this.saveInk();
    this.controller.releaseDocument();
  }

  private filesDir(): string {
    const ctx = getContext(this) as common.UIAbilityContext;
    return ctx.filesDir;
  }

  private penColorOf(kind: number): string {
    return kind === INK_AI ? AI_COLOR : INK_COLOR;
  }

  private penWidth(): number {
    return WIDTHS[this.penWidthIdx];
  }

  // ---- 打开 ----
  private async open(): Promise<void> {
    const doc = new pdfService.PdfDocument();
    try {
      const code = Number(doc.loadDocument(this.pdfPath));
      if (code !== 0) {
        this.note = `打不开（code=${code}）`;
        return;
      }
      const count = doc.getPageCount();
      const p0 = doc.getPage(0);
      // 单位：PDF 点；gap=0
      this.docLayout = { pageW: p0.getWidth(), pageH: p0.getHeight(), gap: 0, count: count };
    } catch (err) {
      this.note = `读取页尺寸失败：${err}`;
      return;
    } finally {
      doc.releaseDocument();
    }

    try {
      this.controller.registerScrollListener((p: pdfViewManager.ScrollParam): void => {
        // 它几乎不触发（实测滚动全程 offY 恒为 0），但一旦来了就是权威值：
        // 用它校正我们自己累计的偏移，防止长期漂移。
        if (p.viewWidth > 0) { this.viewW = p.viewWidth; }
        if (p.viewHeight > 0) { this.viewH = p.viewHeight; }
        this.correctFromParam(p);
        this.drawAll();
      });
      this.controller.registerPageChangedListener((idx: number): void => {
        this.onPageChanged(idx);
      });
      this.controller.registerScaleChangedListener((_s: number): void => {
        this.drawAll();
      });
    } catch (err) {
      hilog.error(0x0000, 'PdfReaderView', `注册监听器失败: ${err}`);
    }

    try {
      const start = this.initialPage > 0 ? this.initialPage : 0;
      const r = await this.controller.loadDocument(this.pdfPath, '', start);
      this.loaded = (Number(r) === 0);
      this.note = this.loaded ? '' : `loadDocument code=${Number(r)}`;
      hilog.info(0x0000, 'PdfReaderView', `loadDocument code=${Number(r)} pages=${this.docLayout.count}`);
      if (this.loaded) {
        // 页缝归零：用户要求「不同页码拼接无间隙」，跨页书写才不会在中缝断开
        try {
          this.controller.setPageSpacing(0, 0);
          hilog.info(0x0000, 'PdfReaderView',
            `pageSpacing h=${this.controller.getPageHorizontalSpacing()} v=${this.controller.getPageVerticalSpacing()}`);
        } catch (err) {
          hilog.error(0x0000, 'PdfReaderView', `setPageSpacing 失败: ${err}`);
        }
        if (this.debugCrossPage) {
          setTimeout((): void => {
            this.injectCrossPage();
          }, 1500);
        }
      }
    } catch (err) {
      this.note = `loadDocument 抛异常：${err}`;
    }
  }

  private onPageChanged(idx: number): void {
    if (idx < 0) {
      return;
    }
    this.pageNo = idx;
    const hw = updateHighWater(this.highWater, idx);
    if (hw !== this.highWater) {
      this.highWater = hw;
    }
    this.drawAll();
  }

  // ---- 坐标：自算线性映射 ----
  //
  // 为什么不用 SDK 的官方换算（pdfPointToViewPoint / viewPointToPDFPoint）：
  // **本机运行时没实现它们**（编译通过、调用即 `is not callable`，与 getCustomPagePixelMap
  // 返回 undefined 同一类"声明在 SDK、运行时不在机器上"）。所以只能自己算。
  //
  // 映射模型（FIT_WIDTH + setPageSpacing(0,0)）：
  //   pxPerPt  = pdfW / pageWpt              （整卷按宽度铺满后的像素/点）
  //   pageHpx  = pageHpt * pxPerPt           （页缝 0，所以页 k 顶边 = k*pageHpx）
  //   originX  = (viewW - pdfW) / 2          （比视口窄时居中）
  //   originY  = -offY                       （offY = 我们累计的滚动像素）
  //   view     = origin + docLocal * pxPerPt
  private pxPerPt: number = 1;
  private pageHpx: number = 0;
  private offY: number = 0;

  private originX(): number {
    return this.viewW > 0 && this.pdfW > 0 ? (this.viewW - this.pdfW) / 2 : 0;
  }

  private maxOffY(): number {
    const total = this.docLayout.count * this.pageHpx;
    const m = total - this.viewH;
    return m > 0 ? m : 0;
  }

  // 记录一次滚动（手指拖动累计 / 书写自动滚屏 / 官方回调校正都走这里）
  private setOffY(v: number): void {
    let y = v;
    if (y < 0) {
      y = 0;
    }
    const mx = this.maxOffY();
    if (y > mx) {
      y = mx;
    }
    this.offY = y;
  }

  // 屏幕点 -> 文档空间点（页内 PDF 点按页累加）
  private toDoc(x: number, y: number): DocPoint {
    const out: DocPoint = { x: 0, y: 0 };
    if (this.pxPerPt <= 0 || this.pageHpx <= 0) {
      return out;
    }
    const docYpx = y + this.offY;
    let page = Math.floor(docYpx / this.pageHpx);
    if (page < 0) { page = 0; }
    if (page >= this.docLayout.count) { page = this.docLayout.count - 1; }
    const localYpx = docYpx - page * this.pageHpx;
    out.x = (x - this.originX()) / this.pxPerPt;
    out.y = page * this.docLayout.pageH + localYpx / this.pxPerPt;
    return out;
  }

  // 文档空间点 -> 屏幕点
  private toView(p: DocPoint): DocPoint {
    const out: DocPoint = { x: -100000, y: -100000 };
    if (this.pageHpx <= 0 || this.pxPerPt <= 0) {
      return out;
    }
    const page = Math.floor(p.y / this.docLayout.pageH);
    const localY = p.y - page * this.docLayout.pageH;
    out.x = this.originX() + p.x * this.pxPerPt;
    out.y = page * this.pageHpx + localY * this.pxPerPt - this.offY;
    return out;
  }

  // 由 ScrollParam 校正（offsetX/offsetY 按文档是 **0..1 的百分比**）
  private correctFromParam(p: pdfViewManager.ScrollParam): void {
    if (p.pdfWidth > 0 && this.docLayout.pageW > 0) {
      this.pdfW = p.pdfWidth;
      this.pxPerPt = p.pdfWidth / this.docLayout.pageW;
      this.pageHpx = this.docLayout.pageH * this.pxPerPt;
    }
    if (p.offsetY >= 0 && p.offsetY <= 1) {
      this.setOffY(p.offsetY * this.maxOffY());
    }
  }

  // ---- 绘制 ----
  private drawAll(): void {
    try {
      const w = this.viewW > 0 ? this.viewW : 1490;
      const h = this.viewH > 0 ? this.viewH : 2483;
      const c = this.ctx;
      c.clearRect(0, 0, w, h);
      for (const s of this.strokes) {
        this.drawRun(s.points, s.color, s.width);
      }
      if (this.live.length > 0) {
        this.drawRun(this.live, this.penColorOf(this.livePen),
          this.livePen === PEN_AI ? 3 : this.penWidth());
      }
    } catch (err) {
      hilog.error(0x0000, 'PdfReaderView', `draw failed: ${err}`);
    }
  }

  // 说明：页缝为 0 时整卷是一个**统一的仿射空间**（每页像素高 pageHpx 恒定），
  // 所以跨页笔迹不需要按页切段 —— 一条 polyline 直接画过去，接缝处天然连续。
  // （旧的自研架构之所以断笔，是因为每页一个 Canvas，物理上被页边界裁开了。）

  private drawRun(pts: Array<DocPoint>, color: string, width: number): void {
    if (pts.length === 0) {
      return;
    }
    const c = this.ctx;
    c.strokeStyle = color;
    c.lineWidth = width;
    c.lineCap = 'round';
    c.lineJoin = 'round';
    c.beginPath();
    let started = false;
    for (const p of pts) {
      const v = this.toView(p);
      if (v.x < -99999) {
        continue;
      }
      if (!started) {
        c.moveTo(v.x, v.y);
        started = true;
      } else {
        c.lineTo(v.x, v.y);
      }
    }
    if (started) {
      c.stroke();
    }
  }

  // ---- 触摸：只处理笔，手指一律放行给 PdfView 滚动 ----
  //
  // 为什么要落笔冻结拖动：本视图里 PdfView 与墨迹 Canvas 是**兄弟节点**（旧架构里 Scroll 是祖先）。
  // Canvas 用 Transparent 才能让手指继续滚，但 Transparent 也让笔的拖动同时传给 PdfView
  // —— 写字时页面会跟着跑。所以落笔冻结、抬笔解冻；笔到边缘时由我们主动滚屏（见 autoScroll）。
  private onTouchEvent(e: TouchEvent): void {
    // 任何触摸（含手指）都先让重绘节拍跑起来，这样滚动时墨迹能跟着页面走
    this.lastTouchMs = Date.now();
    this.ensureTicker();
    const touches = e.touches;
    if (touches.length === 0) {
      return;
    }
    const t = touches[0] as ProbeTouch;
    const tool = t.sourceTool !== undefined ? t.sourceTool : e.sourceTool;
    if (tool !== PEN_TOOL) {
      // 手指：绝不画（产品铁律），但**要借它累计滚动偏移**——
      // registerScrollListener 实测几乎不触发，不自己数就会像上一版那样
      // 墨迹"粘在屏幕绝对位置"、不跟页面走。
      if (e.type === TouchType.Move) {
        if (this.fingerY >= 0) {
          this.setOffY(this.offY - (t.y - this.fingerY));
        }
        this.fingerY = t.y;
      } else if (e.type === TouchType.Down) {
        this.fingerY = t.y;
      } else {
        this.fingerY = -1;
      }
      return;
    }
    this.lastPenX = t.x;
    this.lastPenY = t.y;
    const p = this.toDoc(t.x, t.y);
    if (e.type === TouchType.Down) {
      this.setPageDrag(false);
      this.livePen = this.pen;
      if (this.pen === PEN_ERASER) {
        this.eraseAt(p.x, p.y);
        return;
      }
      this.live = [p];
      this.viewW = this.viewW > 0 ? this.viewW : 1490;
      this.viewH = this.viewH > 0 ? this.viewH : 2483;
    } else if (e.type === TouchType.Move) {
      if (this.pen === PEN_ERASER) {
        this.eraseAt(p.x, p.y);
        return;
      }
      if (this.live.length > 0) {
        const last = this.live[this.live.length - 1];
        const dx = p.x - last.x;
        const dy = p.y - last.y;
        if (dx * dx + dy * dy >= 0.25) {
          this.live.push(p);
        }
      }
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      if (this.live.length > 0) {
        this.commitLive();
      }
      this.setPageDrag(true);
    }
    this.drawAll();
  }

  private setPageDrag(enabled: boolean): void {
    try {
      this.controller.enablePageDrag(enabled, enabled);
    } catch (err) {
      hilog.error(0x0000, 'PdfReaderView', `enablePageDrag(${enabled}) 失败: ${err}`);
    }
  }

  // ---- 重绘节拍：滚动时让墨迹跟着页面走 + 落笔时按边缘自动滚屏 ----
  private ensureTicker(): void {
    if (this.tickTimer !== -1) {
      return;
    }
    this.tickTimer = setInterval((): void => {
      this.onTick();
    }, TICK_MS);
  }

  private stopTicker(): void {
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  private onTick(): void {
    const idleMs = Date.now() - this.lastTouchMs;
    // 抬笔后多跑一拍，覆盖惯性滚动
    if (idleMs > 900) {
      this.stopTicker();
      return;
    }
    if (this.live.length > 0) {
      this.autoScroll();
    }
    this.drawAll();
  }

  // 书写自动滚屏：笔尖进入上下边缘区就滚动页面，
  // 并把滚动后的新位置**继续追加进当前笔画** —— 这就是「写到边缘不断笔」。
  private autoScroll(): void {
    if (this.live.length === 0 || this.viewH <= 0) {
      return;
    }
    let step = 0;
    const bottomZone = this.viewH - EDGE_ZONE;
    if (this.lastPenY > bottomZone) {
      const depth = (this.lastPenY - bottomZone) / EDGE_ZONE;
      step = (depth > 1 ? 1 : depth) * EDGE_MAX_STEP;
    } else if (this.lastPenY < EDGE_ZONE) {
      const depth = (EDGE_ZONE - this.lastPenY) / EDGE_ZONE;
      step = -(depth > 1 ? 1 : depth) * EDGE_MAX_STEP;
    }
    if (step === 0) {
      return;
    }
    // step 是**屏幕像素**，与我们自己累计的 offY 同一单位
    const next = this.offY + step;
    if (next < 0) {
      return;                           // 已经在顶部，别再往上拽
    }
    try {
      this.controller.setViewOffset(0, next, true);
    } catch (err) {
      return;
    }
    // 先按我们请求的位置更新（回调不可靠，不能等它），再续笔
    this.setOffY(next);
    // 页面移动了，笔仍停在原屏幕位置 → 该屏幕位置现在对应新的文档点，续进笔画
    const np = this.toDoc(this.lastPenX, this.lastPenY);
    const last = this.live[this.live.length - 1];
    const dx = np.x - last.x;
    const dy = np.y - last.y;
    if (dx * dx + dy * dy >= 0.25) {
      this.live.push(np);
    }
  }

  private commitLive(): void {
    const pts = simplify(this.live, 0.8);
    this.live = [];
    if (pts.length === 0) {
      return;
    }
    this.strokeSeq++;
    const s: DocStroke = {
      id: this.strokeSeq,
      points: pts,
      color: this.penColorOf(this.livePen),
      width: this.livePen === PEN_AI ? 3 : this.penWidth(),
      kind: this.livePen
    };
    this.strokes.push(s);
    this.dirty = true;
    this.scheduleSave();
    const pages = pagesOfStroke(this.docLayout, s);
    if (pages.length > 1) {
      hilog.info(0x0000, 'PdfReaderView',
        `cross-page stroke id=${s.id} pages=${pages.join(',')} points=${pts.length}`);
    }
  }

  private eraseAt(x: number, y: number): void {
    const p: DocPoint = { x: x, y: y };
    const idx = findHitStroke(this.strokes, p, 8);
    if (idx < 0) {
      return;
    }
    const removed = this.strokes.splice(idx, 1);
    if (removed.length > 0) {
      this.dirty = true;
      this.scheduleSave();
    }
  }

  // ---- 墨迹落盘 ----
  private scheduleSave(): void {
    if (this.saveTimer !== -1) {
      return;
    }
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      this.saveInk();
    }, 400);
  }

  private saveInk(): void {
    if (!this.dirty) {
      return;
    }
    const path = `${this.filesDir()}/docink_${this.inkKey}.json`;
    const ok = writeJsonFile(path, strokesToJson(this.strokes));
    if (ok) {
      this.dirty = false;
    }
    hilog.info(0x0000, 'PdfReaderView', `saveInk ok=${ok} strokes=${this.strokes.length}`);
  }

  private loadInk(): void {
    const path = `${this.filesDir()}/docink_${this.inkKey}.json`;
    if (!fileExists(path)) {
      return;
    }
    const text = readTextFile(path);
    this.strokes = strokesFromJson(text !== null ? text : '');
    this.strokeSeq = this.strokes.length;
    hilog.info(0x0000, 'PdfReaderView', `loadInk strokes=${this.strokes.length}`);
  }

  // 调试：注入一条**跨页**笔迹（从第 a 页 72% 处写到第 b 页 28% 处）
  private injectCrossPage(): void {
    const L = this.docLayout;
    if (L.count < 2 || L.pageH <= 0) {
      return;
    }
    const a = this.pageNo;
    const b = Math.min(L.count - 1, a + 1);
    const pts: Array<DocPoint> = [];
    const x0 = L.pageW * 0.18;
    const x1 = L.pageW * 0.72;
    const y0 = a * L.pageH + L.pageH * 0.72;
    const y1 = b * L.pageH + L.pageH * 0.28;
    for (let i = 0; i <= 24; i++) {
      const t = i / 24;
      pts.push({ x: x0 + (x1 - x0) * t, y: y0 + (y1 - y0) * t });
    }
    this.strokeSeq++;
    const s: DocStroke = {
      id: this.strokeSeq, points: pts, color: AI_COLOR, width: 4, kind: INK_AI
    };
    this.strokes.push(s);
    this.dirty = true;
    this.scheduleSave();
    hilog.info(0x0000, 'PdfReaderView',
      `injectCrossPage pages=${pagesOfStroke(L, s).join(',')} docY=${y0.toFixed(1)}->${y1.toFixed(1)}`);
    this.drawAll();
  }

  private undo(): void {
    if (this.strokes.length === 0) {
      return;
    }
    this.strokes.pop();
    this.dirty = true;
    this.scheduleSave();
    this.drawAll();
  }

  // ---- 顶部笔迹设置栏（位置对齐华为笔记；配色按夜城风）----
  @Builder
  TopPenBar() {
    Row() {
      Text('笔')
        .fontSize(14)
        .fontColor(this.pen === PEN_PLAIN ? '#060B12' : '#F7F0E4')
        .backgroundColor(this.pen === PEN_PLAIN ? '#FF8A2A' : '#22395F')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(6)
        .onClick(() => { this.pen = PEN_PLAIN; })

      Text('问')
        .fontSize(14)
        .fontColor(this.pen === PEN_AI ? '#060B12' : '#F7F0E4')
        .backgroundColor(this.pen === PEN_AI ? '#4C9AFF' : '#22395F')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(6)
        .margin({ left: 6 })
        .onClick(() => { this.pen = PEN_AI; })

      Text('擦')
        .fontSize(14)
        .fontColor(this.pen === PEN_ERASER ? '#060B12' : '#F7F0E4')
        .backgroundColor(this.pen === PEN_ERASER ? '#8CA2C0' : '#22395F')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(6)
        .margin({ left: 6 })
        .onClick(() => { this.pen = PEN_ERASER; })

      Row() {
        ForEach(WIDTHS, (wv: number, i: number) => {
          Stack() {
            Circle({ width: 6 + i * 5, height: 6 + i * 5 })
              .fill(i === this.penWidthIdx ? '#FF8A2A' : '#8CA2C0')
          }
          .width(26)
          .height(26)
          .onClick(() => { this.penWidthIdx = i; })
        }, (wv: number, i: number) => `w_${i}`)
      }
      .margin({ left: 12 })

      Text('撤')
        .fontSize(14).fontColor('#F7F0E4').backgroundColor('#22395F')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(6)
        .margin({ left: 10 })
        .onClick(() => { this.undo(); })

      Blank()

      if (this.debugCrossPage) {
        Text('跨页测试')
          .fontSize(12).fontColor('#060B12').backgroundColor('#8CA2C0')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 }).borderRadius(6)
          .margin({ right: 6 })
          .onClick(() => { this.injectCrossPage(); })
      }
      Text(`${this.highWater + 1}/${this.docLayout.count}`)
        .fontSize(12).fontColor('#8CA2C0')
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#182A47')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  LeftRail() {
    Column() {
      Text('对话').fontSize(11).fontColor('#5A6E8C').margin({ top: 8 })
    }
    .width(RAIL_W)
    .height('100%')
    .backgroundColor('#0B1526')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  RightRail() {
    Column() {
      Text('草稿').fontSize(11).fontColor('#5A6E8C').margin({ top: 8 })
    }
    .width(RAIL_W)
    .height('100%')
    .backgroundColor('#0B1526')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      this.TopPenBar()
      Row() {
        this.LeftRail()
        Stack() {
          if (this.loaded) {
            PdfView({
              controller: this.controller,
              pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
              isContinuous: true,
              showScroll: true,
              pageFit: pdfService.PageFit.FIT_WIDTH
            })
              .width('100%')
              .height('100%')
          } else {
            Text(this.note).fontSize(13).fontColor('#8CA2C0')
          }

          // 墨迹层：盖在 PdfView 上，Transparent 让手指继续能滚（实测有效）
          Canvas(this.ctx)
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.Transparent)
            .onReady(() => {
              this.viewW = this.viewW > 0 ? this.viewW : 1490;
              this.viewH = this.viewH > 0 ? this.viewH : 2483;
              this.drawAll();
            })
            .onTouch((e: TouchEvent) => {
              this.onTouchEvent(e);
            })

          if (this.note !== '' && this.loaded) {
            Text(this.note).fontSize(11).fontColor('#FF8A2A').position({ x: 6, y: 6 })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .onAreaChange((_o: Area, n: Area) => {
          const w = Number(n.width);
          const h = Number(n.height);
          if (w > 0) { this.viewW = w; }
          if (h > 0) { this.viewH = h; }
          this.drawAll();
        })
        this.RightRail()
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(NIGHT)
  }
}
