import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { pageOffsets, totalHeight, pageAt } from '../pdf/ContinuousLayout';
import { renderWindow, absoluteScrollOffset } from '../pdf/RenderWindow';
import { buildPageChunks, visibleChunks, pagesToRelease, PageChunk, CHUNK_MAX_VP,
  CHUNK_WINDOW_MARGIN } from '../pdf/ChunkWindow';
import { indexButtonLabel } from './PresentationMath';
import { updateHighWater } from '../book/ReadingProgress';
import { transformForCrop, DisplayTransform } from '../pdf/ReaderGeometry';
import { BBox } from '../pdf/CropMath';
import { downsampleGrid, regionHint, SampleGrid } from '../pdf/CropPipeline';
import { CROP_DEFAULTS, PageScan, CropResult, PageBox, scanPage, bookCrop,
  boxForPage } from '../pdf/AutoCrop';
import { PdfPageSource } from '../pdf/PdfPageSource';
import { chaptersFromOutline, chapterAt, split, mergeNext, rename, moveBoundary } from '../book/ChapterModel';
import { Chapter, OutlineMarker } from '../core/DocModel';
import { InkStore } from '../ink/InkStore';
import { PageInkCanvas } from '../ink/PageInkCanvas';
import { bubbleOnQuestion, markAnswerReady, markSettled, bubbleScreenY, bubbleDotSize,
  bubbleDotOpacity, foldBubbles, BubblePhase, QuestionBubble } from '../ink/BubbleModel';
import { assemblePrompt, SourceBlock } from '../ai/PromptAssembler';
import { parseAnswer } from '../ai/AnswerParser';
import { LlmClient, ByokStore, ByokConfig, DEFAULT_BASE_URL, DEFAULT_MODEL } from '../ai/LlmClient';
import { routeQuery, QueryRoute } from '../search/QueryRouter';
import { selectBlocks, filterRead, IndexedChunk } from '../search/SearchOrchestrator';
import { LexicalIndex } from '../search/LexicalIndex';
import { VectorIndex } from '../search/VectorIndex';
import { BookIndexer, BuildResult } from '../book/BookIndexer';
import { IndexCache } from '../book/IndexCache';
import { OcrTexts, OcrRecord } from '../book/OcrTexts';
import { isLeftSwipe, extendCap } from '../ink/Gestures';
import { textHash } from '../book/IndexerMath';
import { EmbeddingClient } from '../ai/EmbeddingClient';
import { VisionClient } from '../ai/VisionClient';
import { bookOutlineSummary, chapterExcerpt } from '../ai/ContextSummary';
import { strokesToJson, strokesFromJson } from '../ink/InkPersistence';
import { fileExists, readJsonFile, readTextFile, writeJsonFile } from '../core/JsonFile';
import { KnowledgeBase } from '../search/KnowledgeBase';
import { ReviewQueue, QuizCard } from '../review/ReviewQueue';
import { QaRecord } from '../ai/Qa';
import { bubblesFromQa, QaAnchor } from '../ink/BubbleModel';
import { markersFromTocText } from '../pdf/ScanPipeline';
import { diagnoseOpen, OpenDiagnosis, OpenProblem, PARSE_THREW } from '../pdf/OpenDiagnosis';

// 长卷阅读壳：开书先只探测第 0 页定纵横比，立即全页渲染出首帧；
// 整书裁剪分析（逐页降采样 → 行/列投影 → 四边各自稳健估框，见 pdf/AutoCrop）转后台分批跑。
// 滚动只渲染窗口内页面并回收窗外页（LRU）。
// 每页槽位叠 PageInkCanvas：普通笔黑墨、AI笔液态彩+一笔成形。
const MAX_SAMPLES = 160;
const SEAM_OVERLAP = 12;

// 裁框的落盘结构（ArkTS 不允许无类型对象字面量，必须显式声明）
interface StoredCrop {
  hasShared: boolean;
  shared: PageBox;
  split: boolean;
  even: PageBox;
  odd: PageBox;
  spread: boolean;
}

const NO_CROP_BOX: PageBox = { top: 0, bottom: 1, left: 0, right: 1 };
// 开书分析上限：整本逐页渲染会卡开书；超出部分不裁边（先跑通再优化）
const ANALYZE_MAX_PAGES = 40;
// 建书索引页数上限（v1：前 60 页有文字层即够用，全书索引走 T3）
const INDEX_MAX_PAGES = 60;
const PEN_INK = 1;
const PEN_AI = 2;
const LRU_MARGIN = 1;
// 渐进索引批次：每次「索引」按钮续跑的页数（决策 #29）
const INDEX_BATCH = 60;
// 左缘手势条宽度与左滑阈值
const EDGE_STRIP_W = 24;
const SWIPE_THRESHOLD = 60;
const DRAFT_CANVAS_H = 1500;
// 跨会话恢复气泡的 id 起点（避开会话内新提问 id）
const RESTORED_ID_BASE = 1000000;
// 长卷分块上限 CHUNK_MAX_VP、可见窗口余量、PageChunk 均已抽到 pdf/ChunkWindow（带单测）。

// 每个气泡独立的问答卡状态：并发提问互不串扰
interface BubbleCard {
  phase: number; // 1=思考中 2=完成
  answer: string;
  refPages: Array<number>;
  related: Array<number>;
  notice: string;
}

@Component
export struct ReaderView {
  @Prop pdfPath: string = '';
  @Prop bookTitle: string = '';
  @Prop initialPage: number = -1;
  @State pageTops: Array<number> = [];
  @State slotHeights: Array<number> = [];
  @State canvasHeight: number = 0;
  @State pageImages: Array<image.PixelMap | null> = [];
  @State visibleChunks: Array<PageChunk> = [];
  private allChunks: Array<PageChunk> = [];
  private windowPages: Array<number> = [];
  // 上一帧的渲染窗口；只有它变了才重算 visibleChunks（见 refreshWindow）
  private windowFirst: number = -1;
  private windowLast: number = -1;
  @State highWaterPage: number = 0;
  @State readerPage: number = 0;
  @State scrollY: number = 0;
  @State penMode: number = PEN_INK;
  @State questionCount: number = 0;
  @State chapterTitle: string = '';
  @State chapters: Array<Chapter> = [];
  @State bubbles: Array<QuestionBubble> = [];
  @State expandedBubbleId: number = -1;
  @State byok: ByokConfig = {
    baseUrl: DEFAULT_BASE_URL,
    apiKey: '',
    model: DEFAULT_MODEL,
    embedBaseUrl: '',
    embedModel: '',
    visionBaseUrl: '',
    visionModel: '',
    crossBook: true,
    crossNoticeShown: false
  };
  @State inputBaseUrl: string = DEFAULT_BASE_URL;
  @State inputApiKey: string = '';
  @State inputModel: string = DEFAULT_MODEL;
  @State inputEmbedBase: string = '';
  @State inputEmbedModel: string = '';
  @State inputVisionBase: string = '';
  @State inputVisionModel: string = '';
  @State cards: Map<number, BubbleCard> = new Map(); // 按气泡 id 存卡状态
  @State wholeBook: boolean = false; // 铁律2开关：默认只答已读
  @State chapterPanelOpen: boolean = false;
  @State renameIdx: number = -1;
  @State renameInput: string = '';
  @State draftOpen: boolean = false;
  @State draftAnchor: number = -1;
  @State draftEnd: number = -1;
  @State highlightPage: number = -1;
  @State clampMode: boolean = false;
  @State bubbleInputs: Map<number, string> = new Map(); // 每个气泡独立的输入草稿（@State 使 set 可观察，发送后能清空输入框）

  private cardOf(id: number): BubbleCard {
    const c = this.cards.get(id);
    if (c !== undefined) {
      return c;
    }
    const empty: BubbleCard = { phase: 0, answer: '', refPages: [], related: [], notice: '' };
    return empty;
  }

  private setCard(id: number, card: BubbleCard): void {
    this.cards.set(id, card);
  }

  private cardPhaseOf(id: number): number {
    return this.cardOf(id).phase;
  }

  private cardAnswerOf(id: number): string {
    return this.cardOf(id).answer;
  }

  private cardRefPagesOf(id: number): Array<number> {
    return this.cardOf(id).refPages;
  }

  private cardRelatedPagesOf(id: number): Array<number> {
    return this.cardOf(id).related;
  }

  private cardNoticeOf(id: number): string {
    return this.cardOf(id).notice;
  }

  @State breatheOut: boolean = false;
  // 呼吸律动的定时器句柄（-1 = 未运行）。只在确有「思考中」气泡时运行。
  private breatheTimer: number = -1;
  @State showConfig: boolean = false;
  @State indexStatus: string = '';
  @State analysisStatus: string = '';
  private analyzing: boolean = false;
  private probeGrid: SampleGrid | null = null;
  private restoredQa: Map<number, QaRecord> = new Map();
  @State indexCap: number = INDEX_MAX_PAGES;
  @State inkRevision: number = 0;
  @State loadPhase: number = 0; // 0=加载中 1=就绪 2=打不开
  // 打不开时的成因与文案（pdf/OpenDiagnosis）：区分「文件没了」「格式不支持」「要密码」，
  // 并决定还给不给「重试」——对「文件没了」重试是死路
  @State failInfo: OpenDiagnosis = {
    problem: OpenProblem.Unknown,
    title: '这本书暂时打不开',
    hint: '文件可能已损坏或格式不受支持',
    canRetry: true
  };
  private qaAll: Array<QaRecord> = [];
  private source: PdfPageSource = new PdfPageSource();
  private sampleGrids: Array<SampleGrid> = [];
  private pageScans: Array<PageScan> = [];
  private cropResult: CropResult = {
    shared: null, even: null, odd: null, split: false, spread: false, used: 0, rejected: 0
  };
  private pageCrops: Array<BBox | null> = [];
  private transforms: Array<DisplayTransform> = [];
  private inkStore: InkStore = new InkStore();
  private draftStore: InkStore = new InkStore();
  private ocrTexts: OcrTexts = new OcrTexts();
  private scroller: Scroller = new Scroller();
  private viewWidth: number = 0;
  private viewportHeight: number = 0;
  // 布局重试：视口尺寸（onAreaChange）与页面网格（prepareCore）来自两个事件，
  // 谁先到不确定；早期返回时排有限次重试，避免「永远建不出布局」。
  private layoutRetry: number = -1;
  private layoutRetryLeft: number = 0;
  private layoutReady: boolean = false;
  private pending: Set<number> = new Set();
  private lastSavedWater: number = -1; // 上次落盘的高水位（节流用）
  private inkSaveTimer: number = -1; // 墨迹落盘防抖定时器
  private bookSummaryText: string = '';
  private inkKey: string = 'book';
  private gestureBoxes: Map<number, BBox> = new Map();
  private llm: LlmClient = new LlmClient();
  private byokStore: ByokStore = new ByokStore();
  private askedIds: Set<number> = new Set();
  private lexical: LexicalIndex = new LexicalIndex();
  private vector: VectorIndex = new VectorIndex();
  private indexedChunks: Array<IndexedChunk> = [];
  private indexReady: boolean = false;
  private indexBuilding: boolean = false;
  private reviewQueue: ReviewQueue = new ReviewQueue();

  aboutToAppear(): void {
    if (this.pdfPath === '') {
      return;
    }
    this.byokStore.load(getContext(this) as common.UIAbilityContext)
      .then((cfg: ByokConfig): void => {
        this.byok = cfg;
        this.inputBaseUrl = cfg.baseUrl;
        this.inputApiKey = cfg.apiKey;
        this.inputModel = cfg.model;
        this.inputEmbedBase = cfg.embedBaseUrl;
        this.inputEmbedModel = cfg.embedModel;
        this.inputVisionBase = cfg.visionBaseUrl;
        this.inputVisionModel = cfg.visionModel;
        this.buildIndex();
      })
      .catch((err: Object): void => {
        hilog.error(0x0000, 'ReaderView', `byok load failed: ${err}`);
      });
    this.prepare();
  }

  aboutToDisappear(): void {
    if (this.layoutRetry !== -1) {
      clearTimeout(this.layoutRetry);
      this.layoutRetry = -1;
    }
    if (this.breatheTimer !== -1) {
      clearInterval(this.breatheTimer);
      this.breatheTimer = -1;
    }
    this.flushInk();
    this.saveOcr();
    this.saveProgress();
    this.saveDraft();
    this.saveReview();
    KnowledgeBase.shared().unregister(this.inkKey);
    this.source.close();
  }

  // 「思考中」气泡的呼吸律动。
  //
  // 为什么不用根级无限动画：原先 build() 的 onAppear 里跑 animateTo({ iterations: -1 })
  // 驱动 breatheOut，等于让整个阅读器**每帧重渲染**（一整棵包含 24 页槽位的树）。
  // 改为只在确有 Thinking 气泡时用定时器翻转状态，动画本身挂在气泡元素上。
  private syncBreathe(): void {
    let thinking = false;
    for (const b of this.bubbles) {
      if (b.phase === BubblePhase.Thinking) {
        thinking = true;
        break;
      }
    }
    if (thinking) {
      if (this.breatheTimer === -1) {
        this.breatheTimer = setInterval((): void => {
          this.breatheOut = !this.breatheOut;
        }, 2500);
      }
    } else if (this.breatheTimer !== -1) {
      clearInterval(this.breatheTimer);
      this.breatheTimer = -1;
      this.breatheOut = false;
    }
  }

  // 开书外壳：任何一步异常都不能静默空白——落错误态并留日志
  private async prepare(): Promise<void> {
    try {
      await this.prepareCore();
    } catch (err) {
      hilog.error(0x0000, 'ReaderView', `prepare failed: ${err}`);
      this.failInfo = diagnoseOpen(PARSE_THREW, fileExists(this.pdfPath));
      this.loadPhase = 2;
    }
  }

  private async prepareCore(): Promise<void> {
    if (!this.source.open(this.pdfPath)) {
      const code = this.source.lastParseCode();
      this.failInfo = diagnoseOpen(code, fileExists(this.pdfPath));
      hilog.error(0x0000, 'ReaderView',
        `open pdf failed: ${this.pdfPath} code=${code} problem=${this.failInfo.problem}`);
      this.loadPhase = 2;
      return;
    }
    this.loadPhase = 1;
    const n = this.source.pageCount();
    hilog.info(0x0000, 'ReaderView', `pdf opened pages=${n}`);
    // 书的唯一键 = 文件路径哈希（同页数的书不再串书）
    this.inkKey = 'b' + textHash(this.pdfPath);
    this.loadReview();
    this.loadInk();
    this.loadDraft();
    this.loadOcr();
    this.loadQa();
    // 单次遍历同时产出气泡锚点与本书的恢复存档
    const anchors: Array<QaAnchor> = [];
    this.restoredQa = new Map();
    let rid = RESTORED_ID_BASE;
    for (const rec of this.qaAll) {
      const ay = rec.anchorY === undefined ? 0 : rec.anchorY;
      anchors.push({ bookKey: rec.bookKey, pageIndex: rec.pageIndex, anchorY: ay });
      if (rec.bookKey === this.inkKey) {
        this.restoredQa.set(rid, rec);
        rid++;
      }
    }
    this.bubbles = bubblesFromQa(anchors, this.inkKey, RESTORED_ID_BASE);
    this.trackScrollForBubbles();
    const isNew = !this.hasProgress();
    this.loadProgress();
    const saved = this.loadChapters(n);
    if (saved !== null) {
      this.chapters = saved;
    } else {
      this.chapters = chaptersFromOutline(this.source.outlineMarkers(), n);
    }
    this.bookSummaryText = bookOutlineSummary(this.chapters, 400);
    // 快速首帧：只采样第 0 页定纵横比，全部页先按无裁剪全页渲染；
    // 整书版式（裁剪）分析转后台，完成后重排。
    const neutral: PageScan = { box: null, spread: false, ink: 0 };
    this.pageScans = new Array<PageScan>(n).fill(neutral);
    const fallback: SampleGrid = downsampleGrid(594, 840, MAX_SAMPLES);
    try {
      const probe = await this.source.sampleGray(0, MAX_SAMPLES);
      this.probeGrid = (probe !== null) ? probe.grid : fallback;
    } catch (err) {
      hilog.error(0x0000, 'ReaderView', `probe page0 failed: ${err}`);
      this.probeGrid = fallback;
    }
    for (let i = 0; i < n; i++) {
      this.sampleGrids.push(this.probeGrid);
      this.pageCrops.push(null);
    }
    // 算过的书直接读回裁框：第二次之后开书不必再逐页采样，版心也从第一帧就是最终值
    const hadCrop = this.loadCrop();
    if (hadCrop) {
      this.applyBookCrop();
      hilog.info(0x0000, 'ReaderView', `autoCrop loaded from disk (shared=${this.cropResult.shared !== null} split=${this.cropResult.split})`);
    }
    // 允许布局重试：此刻 onAreaChange 可能还没到（viewWidth 仍是 0）
    this.layoutRetryLeft = 30;
    this.rebuildLayout();
    if (isNew && this.chapters.length <= 1) {
      // 「要不要先夹一章？」轻问：自动展开夹子面板，跳过也完全不影响功能
      this.chapterPanelOpen = true;
    }
    if (this.initialPage > 0 && this.initialPage < n) {
      setTimeout((): void => {
        this.jumpToPage(this.initialPage);
      }, 300);
    }
    if (!hadCrop) {
      this.analyzeInBackground(n, Math.min(n, Math.max(ANALYZE_MAX_PAGES, this.indexCap)));
    }
  }

  // 整书版式分析：逐页降采样 → 墨迹包围盒 → 奇偶簇。
  // 后台分批跑，每批让出 UI 线程；完成后统一应用簇裁剪并重排。
  private async analyzeInBackground(n: number, analyzeCount: number): Promise<void> {
    if (this.analyzing) {
      return;
    }
    this.analyzing = true;
    const fallback: SampleGrid = (this.probeGrid !== null) ? this.probeGrid
      : downsampleGrid(594, 840, MAX_SAMPLES);
    const grids: Array<SampleGrid> = [];
    const scans: Array<PageScan> = [];
    try {
      for (let i = 0; i < analyzeCount; i++) {
        try {
          const sample = await this.source.sampleGray(i, MAX_SAMPLES);
          if (sample === null) {
            grids.push(fallback);
            scans.push({ box: null, spread: false, ink: 0 });
          } else {
            // 自适应阈值 + 行/列投影 + 噪声抑制，见 pdf/AutoCrop
            grids.push(sample.grid);
            scans.push(scanPage(sample.gray, sample.grid.cols, sample.grid.rows, CROP_DEFAULTS));
          }
        } catch (err) {
          grids.push(fallback);
          scans.push({ box: null, spread: false, ink: 0 });
          hilog.error(0x0000, 'ReaderView', `sample page ${i} failed: ${err}`);
        }
        if (i % 8 === 7) {
          this.analysisStatus = `版式 ${i + 1}/${analyzeCount}`;
          await new Promise<void>((resolve: () => void) => {
            setTimeout(resolve, 0);
          });
        }
      }
      for (let i = 0; i < analyzeCount; i++) {
        this.sampleGrids[i] = grids[i];
        this.pageScans[i] = scans[i];
      }
      this.computeBookCrop(analyzeCount);
      // 版式重排会改页槽高度：按当前阅读页顶部回滚视口，避免正在读的位置跳变
      const anchorPage = this.readerPage;
      this.rebuildLayout();
      if (anchorPage > 0 && anchorPage < this.pageTops.length) {
        this.scroller.scrollTo({ xOffset: 0, yOffset: this.pageTops[anchorPage], animation: false });
      }
      hilog.info(0x0000, 'ReaderView', `layout analysis done ${analyzeCount}/${n}`);
    } catch (err) {
      hilog.error(0x0000, 'ReaderView', `layout analysis failed: ${err}`);
    } finally {
      this.analysisStatus = '';
      this.analyzing = false;
    }
  }

  // 采样栅格 bbox → 页面像素 bbox。必须先换算再进 ReaderGeometry：
  // ReaderGeometry 只在页面坐标（像素）里工作，直接喂栅格坐标会忽略 stepX/stepY 各向异性
  // （stepY/stepX≈1.37），槽位高度偏小 37% → Image 被塞进比例错误的盒子，每页上下被切掉。
  private cropBoxForPage(i: number): BBox | null {
    const pb = boxForPage(this.cropResult, i);
    if (pb === null || i < 0 || i >= this.sampleGrids.length) {
      return null;
    }
    const g = this.sampleGrids[i];
    const left = Math.max(0, Math.floor(pb.left * g.cols));
    const top = Math.max(0, Math.floor(pb.top * g.rows));
    const right = Math.min(g.cols - 1, Math.ceil(pb.right * g.cols) - 1);
    const bottom = Math.min(g.rows - 1, Math.ceil(pb.bottom * g.rows) - 1);
    if (right <= left || bottom <= top) {
      return null;
    }
    const box: BBox = { left: left, top: top, right: right, bottom: bottom };
    return box;
  }

  // 把「全书内容框」落到每一页上。
  //
  // 关键改进：框是**整本一个**（或按奇偶各一），所以**未分析页也用同一个框**，
  // 不再出现"前 20 页裁了、后面的没裁"那种读到一半版心突变的情况；
  // 而且一旦算稳（或从磁盘读回），它就不再变，翻页时版心恒定。
  private applyBookCrop(): void {
    if (this.cropResult.shared === null && !this.cropResult.split) {
      return;
    }
    for (let i = 0; i < this.pageCrops.length; i++) {
      this.pageCrops[i] = this.cropBoxForPage(i);
    }
  }

  // 用已扫描的页做稳健估计，算稳了就落盘（下次开书直接读回，连重排都省了）
  private computeBookCrop(analyzeCount: number): void {
    const scans: Array<PageScan> = [];
    for (let i = 0; i < analyzeCount && i < this.pageScans.length; i++) {
      scans.push(this.pageScans[i]);
    }
    const r = bookCrop(scans, CROP_DEFAULTS);
    this.cropResult = r;
    this.applyBookCrop();
    hilog.info(0x0000, 'ReaderView', `autoCrop used=${r.used} rejected=${r.rejected} ` +
      `split=${r.split} spread=${r.spread} shared=${r.shared !== null} ` +
      `box=${r.shared !== null ? `${r.shared.top.toFixed(3)},${r.shared.bottom.toFixed(3)},` +
        `${r.shared.left.toFixed(3)},${r.shared.right.toFixed(3)}` : 'none'}`);
    if (r.shared !== null || r.split) {
      this.saveCrop();
    }
  }

  private loadCrop(): boolean {
    const obj = readJsonFile<StoredCrop>(`${this.filesDir()}/crop_${this.inkKey}.json`);
    if (obj === undefined || obj === null) {
      return false;
    }
    if (obj.hasShared !== true && obj.split !== true) {
      return false;
    }
    const r: CropResult = {
      shared: obj.hasShared === true ? obj.shared : null,
      even: obj.split === true ? obj.even : null,
      odd: obj.split === true ? obj.odd : null,
      split: obj.split === true,
      spread: obj.spread === true,
      used: 0,
      rejected: 0
    };
    this.cropResult = r;
    return true;
  }

  private saveCrop(): void {
    const r = this.cropResult;
    if (r.shared === null && !r.split) {
      return;
    }
    const obj: StoredCrop = {
      hasShared: r.shared !== null,
      shared: r.shared !== null ? r.shared : NO_CROP_BOX,
      split: r.split,
      even: r.even !== null ? r.even : NO_CROP_BOX,
      odd: r.odd !== null ? r.odd : NO_CROP_BOX,
      spread: r.spread
    };
    writeJsonFile(`${this.filesDir()}/crop_${this.inkKey}.json`, JSON.stringify(obj));
  }

  private rebuildLayout(): void {
    if (this.sampleGrids.length === 0 || this.viewWidth <= 0) {
      // 这里**绝不能静默返回**。viewWidth 来自容器的 onAreaChange、sampleGrids 来自
      // prepareCore，两个事件谁先到不确定；两者先后不巧时会一路跳过，而此后没有任何事件
      // 再触发布局——表现为「书打开了、工具栏都在，但一页都不渲染」，且日志里一句错都没有
      //（真机实测：Image 节点 0 个、页码恒为 P1）。
      hilog.warn(0x0000, 'ReaderView',
        `rebuildLayout pending grids=${this.sampleGrids.length} viewWidth=${this.viewWidth} retryLeft=${this.layoutRetryLeft}`);
      if (this.layoutRetry === -1 && this.layoutRetryLeft > 0) {
        this.layoutRetry = setTimeout((): void => {
          this.layoutRetry = -1;
          this.layoutRetryLeft--;
          this.rebuildLayout();
        }, 100);
      }
      return;
    }
    const tops: Array<number> = [];
    const slotH: Array<number> = [];
    const images: Array<image.PixelMap | null> = [];
    const transforms: Array<DisplayTransform> = [];
    for (let i = 0; i < this.sampleGrids.length; i++) {
      const grid = this.sampleGrids[i];
      // 页面像素尺寸与裁剪框都走采样栅格：各轴用各自步长（见 transformForCrop 注释），
      // 否则槽位高度会小 stepY/stepX 倍，每页上下被切掉。
      const t = transformForCrop(grid.cols * grid.stepX, grid.rows * grid.stepY,
        this.pageCrops[i], this.viewWidth, grid.stepX, grid.stepY);
      tops.push(0);
      slotH.push(t.contentHeight);
      images.push(null);
      transforms.push(t);
    }
    this.pageTops = pageOffsets(slotH, SEAM_OVERLAP);
    this.slotHeights = slotH;
    this.canvasHeight = totalHeight(slotH, SEAM_OVERLAP);
    this.pageImages = images;
    this.transforms = transforms;
    this.allChunks = this.buildChunks();
    this.layoutReady = true;
    // 版式重算后位图全被清空，必须强制重算一次渲染窗口
    this.windowFirst = -1;
    this.windowLast = -1;
    // 位置必须取**实时绝对 offset**：this.scrollY 只在有气泡时才维护（纯阅读零重渲染），
    // 读它会把渲染窗口错误地算回 y≈0，眼前整屏变占位空白。
    this.refreshWindow(this.liveOffset());
  }

  // 分块规则与 CHUNK_MAX_VP 约束见 pdf/ChunkWindow（带单测）
  private buildChunks(): Array<PageChunk> {
    return buildPageChunks(this.pageTops, this.slotHeights, CHUNK_MAX_VP);
  }

  // 窗口与占位规则见 pdf/ChunkWindow.visibleChunks（带单测）
  //
  // y 必须**由调用方按绝对滚动位置传进来**，绝不能读 this.scrollY：scrollY 是给气泡跟随
  // 用的 @State，纯阅读时按设计不逐帧写（保持零重渲染），读它就会永远是 0 —— 于是所有块
  // 都被判为「窗口外」、pages 清空，眼前整屏都是等高空占位，表现为「根本看不到内容」。
  private refreshChunks(y: number): void {
    const ready: Array<boolean> = [];
    for (let i = 0; i < this.pageImages.length; i++) {
      ready.push(this.pageImages[i] !== null);
    }
    this.visibleChunks = visibleChunks(this.allChunks, y, this.viewportHeight,
      ready, CHUNK_WINDOW_MARGIN);
  }

  private refreshWindow(y: number): void {
    if (!this.layoutReady) {
      return;
    }
    // 位置：**没有气泡时一个 @State 都不写**（纯阅读零重渲染）；
    // 有气泡时气泡要跟着内容走，才逐帧同步 scrollY。
    if (this.bubbles.length > 0 && Math.abs(y - this.scrollY) >= 0.5) {
      this.scrollY = y;
    }
    const viewport = this.viewportHeight > 0 ? this.viewportHeight : 600;
    const range = renderWindow(this.pageTops, y, viewport, 1);
    const page = pageAt(this.pageTops, y);
    // 这三个只在取值真的变了才写；逐帧写 @State 会让整棵树每帧重渲染（卡顿来源）
    if (page !== this.readerPage) {
      this.readerPage = page;
    }
    const hw = updateHighWater(this.highWaterPage, page);
    if (hw !== this.highWaterPage) {
      this.highWaterPage = hw;
    }
    const idx = chapterAt(this.chapters, this.highWaterPage);
    if (idx >= 0 && this.chapters[idx].title !== this.chapterTitle) {
      this.chapterTitle = this.chapters[idx].title;
    }
    // 渲染窗口没变就别碰 visibleChunks：它的键一变，整块的 PageInkCanvas 会被重挂，
    // 既打断正在写的笔画，也是滑动时的主要卡顿来源
    if (range.first === this.windowFirst && range.last === this.windowLast) {
      return;
    }
    this.windowFirst = range.first;
    this.windowLast = range.last;
    const indices: Array<number> = [];
    for (let i = range.first; i <= range.last; i++) {
      indices.push(i);
      this.requestPage(i);
    }
    // LRU 回收：窗外页释放位图，内存有界
    const loaded: Array<boolean> = [];
    for (let i = 0; i < this.pageImages.length; i++) {
      loaded.push(this.pageImages[i] !== null);
    }
    for (const i of pagesToRelease(range, loaded, LRU_MARGIN)) {
      this.pageImages[i] = null;
    }
    this.windowPages = indices;
    this.refreshChunks(y);
  }

  private requestPage(i: number): void {
    if (i < 0 || i >= this.pageCrops.length) {
      return;
    }
    if (this.pageImages[i] !== null || this.pending.has(i)) {
      return;
    }
    this.pending.add(i);
    this.renderInto(i);
  }

  private async renderInto(i: number): Promise<void> {
    try {
      const pm = await this.source.pagePixelCopy(i, this.pageCrops[i], this.sampleGrids[i]);
      this.pending.delete(i);
      if (pm !== null && i < this.pageImages.length) {
        this.pageImages[i] = pm;
        // 块键含已就绪位图数：位图就位后重算可见块，触发 ForEach 键变化重建。
        // 位置取实时绝对 offset——**不能读 scrollY**（见 refreshChunks 注释）。
        this.refreshChunks(this.liveOffset());
      } else {
        hilog.error(0x0000, 'ReaderView', `render page ${i} null pm`);
      }
    } catch (err) {
      this.pending.delete(i);
      hilog.error(0x0000, 'ReaderView', `render page ${i} failed: ${err}`);
    }
  }

  private onGesture(pageIndex: number, bbox: BBox): void {
    this.questionCount++;
    const id = this.questionCount;
    this.bubbles.push(bubbleOnQuestion(id, pageIndex, bbox.top));
    this.trackScrollForBubbles();
    this.gestureBoxes.set(id, bbox);
    this.syncBreathe();
    hilog.info(0x0000, 'ReaderView',
      `question gesture @page=${pageIndex} pageBBox=(${bbox.left},${bbox.top},${bbox.right},${bbox.bottom})`);
    // 演示态（未配 key 时）：1.5s 模拟回答完成、再过 2.5s 收敛；配置后走真实问答流
    if (this.byok.apiKey === '') {
      setTimeout((): void => {
        this.bubbles = this.bubbles.map((b: QuestionBubble): QuestionBubble =>
          b.id === id ? markAnswerReady(b) : b);
        this.syncBreathe();
      }, 1500);
      setTimeout((): void => {
        this.bubbles = this.bubbles.map((b: QuestionBubble): QuestionBubble =>
          b.id === id ? markSettled(b) : b);
        this.syncBreathe();
      }, 4000);
    }
  }

  private onBubbleTap(b: QuestionBubble): void {
    if (this.expandedBubbleId === b.id) {
      this.expandedBubbleId = -1;
      return;
    }
    this.expandedBubbleId = b.id;
    // 恢复的历史气泡：直显当时的问答存档，零费用
    if (b.id >= RESTORED_ID_BASE) {
      const rec = this.restoredQa.get(b.id);
      if (rec !== undefined) {
        this.setCard(b.id, {
          phase: 2,
          answer: rec.answer,
          refPages: [rec.pageIndex],
          related: [],
          notice: `${rec.chapterTitle} · ${rec.question}`
        });
      }
      return;
    }
    if (this.byok.apiKey === '') {
      this.offlineLookup(b);
      return;
    }
    const hasPrev = this.askedIds.has(b.id);
    this.askedIds.add(b.id);
    this.askBubble(b, '', hasPrev);
  }

  private sendQuestion(b: QuestionBubble): void {
    if (this.byok.apiKey === '') {
      this.offlineLookup(b);
      return;
    }
    const q = this.bubbleInput(b);
    this.bubbleInputs.set(b.id, '');
    this.askBubble(b, q, true);
  }

  // 离线纯检索模式：只列相关位置与摘录，不生成回答（BYOK 未配置时）
  private offlineLookup(b: QuestionBubble): void {
    const refPages: Array<number> = [];
    if (this.indexReady) {
      const q = this.bubbleInput(b).trim() === '' ? '核心概念' : this.bubbleInput(b).trim();
      const hits = this.lexical.search(q, 4);
      for (const id of hits) {
        for (const c of this.indexedChunks) {
          if (c.id === id) {
            refPages.push(c.pageIndex);
            break;
          }
        }
      }
    }
    this.setCard(b.id, {
      phase: 2,
      answer: '离线模式：只找位置，不生成回答（配置 BYOK 后可提问）',
      refPages: refPages,
      related: [],
      notice: ''
    });
  }

  // 问答流外壳：异常兜底——任何 await 拒绝都不能把气泡永远留在「思考中」
  private async askBubble(b: QuestionBubble, userQuestion: string, hasPrev: boolean): Promise<void> {
    if (this.byok.apiKey === '') {
      return;
    }
    this.setCard(b.id, {
      phase: 1,
      answer: '',
      refPages: [],
      related: [],
      notice: ''
    });
    try {
      await this.askBubbleCore(b, userQuestion, hasPrev);
    } catch (err) {
      hilog.error(0x0000, 'ReaderView', `askBubble failed: ${err}`);
      this.setCard(b.id, {
        phase: 2,
        answer: '回答失败，请重试',
        refPages: [],
        related: [],
        notice: ''
      });
      this.bubbles = this.bubbles.map((x: QuestionBubble): QuestionBubble =>
        x.id === b.id ? markAnswerReady(x) : x);
    }
    setTimeout((): void => {
      this.bubbles = this.bubbles.map((x: QuestionBubble): QuestionBubble =>
        x.id === b.id ? markSettled(x) : x);
    }, 2000);
  }

  // 问答流：路由决策 → T1圈选OCR（扫描书）→ L4检索（铁律2预过滤）→ T0页文本兜底
  // → L1/L2 上下文 → 流式作答 → 引用校验 → 沉淀测验卡。
  private async askBubbleCore(b: QuestionBubble, userQuestion: string, hasPrev: boolean): Promise<void> {
    let notice = '';
    let answer = '';
    let refPages: Array<number> = [];
    let related: Array<number> = [];
    // 展示用问句与提示词问句分离：区域聚焦指令是提示词工程，不应存进复习卡/归档
    const displayQuestion = userQuestion.trim() === '' ? '用中文解释这一页的核心概念，面向初学者' : userQuestion.trim();
    let question = displayQuestion;
    // T1：无文字层的页先转录圈选区域
    let circledContent = '';
    const vision = new VisionClient(this.byok.visionBaseUrl, this.byok.apiKey, this.byok.visionModel);
    let pageTextPre = this.source.pageText(b.pageIndex);
    if (pageTextPre.trim() === '' && this.ocrTexts.has(b.pageIndex)) {
      // T3：已建全书 OCR 索引的扫描书，页级上下文读 OCR 缓存
      pageTextPre = this.ocrTexts.get(b.pageIndex);
    }
    if (pageTextPre.trim() !== '' && this.gestureBoxes.has(b.id)) {
      // 原生 PDF：文字层整页可用，用区域百分比提示聚焦
      const box0 = this.gestureBoxes.get(b.id) as BBox;
      question += `（用户圈选了${regionHint(box0, this.sampleGrids[b.pageIndex],
        this.sampleGrids[b.pageIndex].cols * this.sampleGrids[b.pageIndex].stepX,
        this.sampleGrids[b.pageIndex].rows * this.sampleGrids[b.pageIndex].stepY)}，请聚焦该区域作答）`;
    }
    if (pageTextPre.trim() === '' && vision.available() && this.gestureBoxes.has(b.id)) {
      const box = this.gestureBoxes.get(b.id) as BBox;
      const b64 = await this.source.regionJpegBase64(b.pageIndex, box,
        this.sampleGrids[b.pageIndex], 0.15);
      if (b64 !== '') {
        const ocr = await vision.extractText(b64, 'image/jpeg');
        if (ocr.trim() !== '') {
          circledContent = '圈选区域原文：' + ocr;
        }
      }
    }
    const route = routeQuery(circledContent !== '' || this.gestureBoxes.has(b.id), question, hasPrev);
    let blocks: Array<SourceBlock> = [];
    const crossBlockIds: Array<number> = []; // 跨书块的引用编号：其页码属另一本书，不产出本书跳转
    if (this.indexReady && (route === QueryRoute.LocateInBook || route === QueryRoute.General)) {
      const embed = new EmbeddingClient(this.byok.embedBaseUrl, this.byok.apiKey, this.byok.embedModel);
      let qvec: Array<number> = [];
      if (embed.available()) {
        const vecs = await embed.embed([question]);
        if (vecs.length === 1) {
          qvec = vecs[0];
        }
      }
      const readable = filterRead(this.indexedChunks, this.highWaterPage, this.wholeBook);
      const lexRanking = this.lexical.search(question, 30);
      const vecRanking = qvec.length > 0 ? this.vector.search(qvec, 30) : [];
      const sel = selectBlocks(qvec, lexRanking, vecRanking, readable, 0.6, 3600);
      blocks = sel.blocks;
      // 统一知识库：位置检索时跨书补块（出处带书名，决策 #14，可关）。
      // 跨书块不产出本书页码跳转——页码属另一本书，在本书内解释会跳错页
      if (this.byok.crossBook && route === QueryRoute.LocateInBook) {
        const cross = KnowledgeBase.shared().searchCrossBook(question, 2);
        for (const hit of cross) {
          if (hit.bookKey === this.inkKey) {
            continue;
          }
          const sb: SourceBlock = {
            id: blocks.length + 1,
            sourceLine: `《${hit.bookTitle}》${hit.chunk.sourceLine}`,
            text: hit.chunk.text
          };
          blocks.push(sb);
          crossBlockIds.push(sb.id);
          if (!this.byok.crossNoticeShown) {
            notice = '已引用其他书的内容，可在设置关闭';
            this.byok.crossNoticeShown = true;
            this.byokStore.save(getContext(this) as common.UIAbilityContext, this.byok);
          }
          if (blocks.length >= 8) {
            break;
          }
        }
      }
    }
    // L5 笔记：本书最近两条问答作为上下文
    let notes = '';
    const mine: Array<QaRecord> = [];
    for (const rec of this.qaAll) {
      if (rec.bookKey === this.inkKey) {
        mine.push(rec);
      }
    }
    if (mine.length > 0) {
      const tail = mine.slice(-2);
      const parts: Array<string> = [];
      for (const rec of tail) {
        parts.push(`问：${rec.question} 答：${rec.answer.substring(0, 80)}`);
      }
      notes = parts.join('；');
    }
    const pageText = pageTextPre.length > 1200 ? pageTextPre.substring(0, 1200) : pageTextPre;
    // L2（stable）只放章范围与章首摘录；当前页原文属 L3（dynamic），避免翻页打破前缀缓存
    let chapterContext = '';
    const chIdx = chapterAt(this.chapters, b.pageIndex);
    if (chIdx >= 0) {
      const chp = this.chapters[chIdx];
      let firstText = this.source.pageText(chp.firstPage);
      if (firstText.trim() === '' && this.ocrTexts.has(chp.firstPage)) {
        firstText = this.ocrTexts.get(chp.firstPage);
      }
      chapterContext = chapterExcerpt(chp.firstPage, chp.lastPage, firstText, 300);
    }
    if (pageText !== '') {
      circledContent += (circledContent === '' ? '' : '；') + '当前页原文：' + pageText;
    }
    const prompt = assemblePrompt({
      bookSummary: this.bookSummaryText,
      chapterContext: chapterContext,
      circledContent: circledContent,
      blocks: blocks,
      notes: notes,
      question: question
    });
    const stream = await this.llm.chatStream(this.byok, prompt.stable, prompt.dynamic,
      (fullText: string): void => {
        this.setCard(b.id, {
          phase: 1,
          answer: fullText,
          refPages: [],
          related: [],
          notice: notice
        });
      });
    const validIds: Array<number> = [];
    for (const blk of blocks) {
      validIds.push(blk.id);
    }
    const parsed = parseAnswer(stream.text, validIds);
    answer = parsed.text;
    refPages = [];
    for (const rn of parsed.refs) {
      if (rn >= 1 && rn <= blocks.length) {
        const line = blocks[rn - 1].sourceLine;
        // 跨书块的页码属另一本书，不产出本书跳转
        if (crossBlockIds.indexOf(rn) >= 0) {
          continue;
        }
        // 只认 P{n} 形式的页码：书名里的裸数字（《1984》）不能劫持跳转
        const m = /P(\d+)/.exec(line);
        if (m !== null) {
          refPages.push(parseInt(m[1], 10) - 1);
        }
      }
    }
    // 「相关位置」= 检索给出但未被引用的其余块（设计：卡片末尾的相关位置列表，按阅读顺序排列）
    related = [];
    for (const blk of blocks) {
      if (crossBlockIds.indexOf(blk.id) >= 0) {
        continue;
      }
      const m = /P(\d+)/.exec(blk.sourceLine);
      if (m === null) {
        continue;
      }
      const pg = parseInt(m[1], 10) - 1;
      if (refPages.indexOf(pg) < 0 && related.indexOf(pg) < 0) {
        related.push(pg);
      }
    }
    related.sort((a, b) => a - b);
    // 沉淀测验卡与问答记录（书房管家/归档的材料来源）。
    // 流失败时返回文本是错误描述，绝不入库，只提示原因。
    let failedNotice = '';
    if (stream.failed) {
      failedNotice = '请求失败，本次回答未存入笔记与复习';
    } else if (parsed.text.trim() !== '') {
      // 卡 id 加时间戳：会话内 questionCount 会重数，裸 id 跨会话碰撞会让新提问静默丢卡
      this.reviewQueue.addQuiz(`${this.inkKey}_${b.id}_${Date.now()}`, this.bookTitle, b.pageIndex + 1,
        displayQuestion, parsed.text.substring(0, 200), Date.now());
      this.saveReview();
      const chIdx2 = chapterAt(this.chapters, b.pageIndex);
      const gb = this.gestureBoxes.get(b.id);
      const rec: QaRecord = {
        bookKey: this.inkKey,
        bookTitle: this.bookTitle,
        bookPath: this.pdfPath,
        pageIndex: b.pageIndex,
        anchorY: gb !== undefined ? gb.top : 0,
        chapterTitle: chIdx2 >= 0 ? this.chapters[chIdx2].title : '全书',
        question: displayQuestion,
        answer: parsed.text.substring(0, 300),
        createdAt: Date.now()
      };
      this.appendQa(rec);
    }
    this.setCard(b.id, {
      phase: 2,
      answer: answer,
      refPages: refPages,
      related: related,
      notice: failedNotice === '' ? notice : failedNotice
    });
    this.bubbles = this.bubbles.map((x: QuestionBubble): QuestionBubble =>
      x.id === b.id ? markAnswerReady(x) : x);
  }

  private jumpToPage(pageIndex: number): void {
    if (pageIndex < 0 || pageIndex >= this.pageTops.length) {
      return;
    }
    this.scroller.scrollTo({ xOffset: 0, yOffset: this.pageTops[pageIndex], animation: true });
    this.highlightPage = pageIndex;
    setTimeout((): void => {
      this.highlightPage = -1;
    }, 2000);
  }

  // ---------- 进度/章节/QA 持久化（读写统一走 JsonFile：原子写 + 坏文件兜底） ----------
  private filesDir(): string {
    return (getContext(this) as common.UIAbilityContext).filesDir;
  }

  private hasProgress(): boolean {
    return fileExists(`${this.filesDir()}/progress_${this.inkKey}.json`);
  }

  private loadProgress(): void {
    const obj = readJsonFile<Record<string, Object>>(`${this.filesDir()}/progress_${this.inkKey}.json`);
    if (obj === null) {
      return;
    }
    const hw = obj['highWater'] as number;
    if (hw > this.highWaterPage) {
      this.highWaterPage = hw;
    }
    const cap = obj['indexCap'] as number;
    if (cap >= INDEX_MAX_PAGES) {
      this.indexCap = cap;
    }
  }

  private saveProgress(): void {
    const obj: Record<string, Object> = { 'highWater': this.highWaterPage, 'indexCap': this.indexCap };
    writeJsonFile(`${this.filesDir()}/progress_${this.inkKey}.json`, JSON.stringify(obj));
  }

  private loadChapters(n: number): Array<Chapter> | null {
    const arr = readJsonFile<Array<Chapter>>(`${this.filesDir()}/chapters_${this.inkKey}.json`);
    return (arr !== null && arr.length > 0) ? arr : null;
  }

  private applyChapters(next: Array<Chapter>): void {
    this.chapters = next;
    this.bookSummaryText = bookOutlineSummary(this.chapters, 400);
    writeJsonFile(`${this.filesDir()}/chapters_${this.inkKey}.json`, JSON.stringify(next));
  }

  private loadQa(): void {
    const arr = readJsonFile<Array<QaRecord>>(`${this.filesDir()}/qa.json`);
    if (arr !== null) {
      this.qaAll = arr;
    }
  }

  private appendQa(rec: QaRecord): void {
    this.qaAll.push(rec);
    writeJsonFile(`${this.filesDir()}/qa.json`, JSON.stringify(this.qaAll));
  }

  // T2：扫描书目录识章——视觉转录前几页，解析章节标记
  private async recognizeToc(): Promise<void> {
    const vision = new VisionClient(this.byok.visionBaseUrl, this.byok.apiKey, this.byok.visionModel);
    if (!vision.available()) {
      return;
    }
    const n = this.source.pageCount();
    const markers: Array<OutlineMarker> = [];
    for (let i = 1; i <= Math.min(5, n - 1); i++) {
      let text = this.ocrTexts.has(i) ? this.ocrTexts.get(i) : '';
      if (text === '') {
        const b64 = await this.source.regionJpegBase64(i, null, this.sampleGrids[i], 0);
        if (b64 === '') {
          continue;
        }
        text = await vision.extractText(b64, 'image/jpeg');
      }
      const found = markersFromTocText(text);
      for (const m of found) {
        markers.push(m);
      }
    }
    if (markers.length > 0) {
      this.applyChapters(chaptersFromOutline(markers, n));
    }
  }

  // ---------- 墨迹持久化 ----------
  private loadInk(): void {
    // 墨迹文件是 strokesToJson 的原始文本，不走 JSON 解析（flat 点格式由 strokesFromJson 转换）
    const json = readTextFile(`${this.filesDir()}/ink_${this.inkKey}.json`);
    if (json !== null && json.trim() !== '') {
      this.inkStore.loadFrom(strokesFromJson(json));
    }
  }

  // 逐笔全量序列化代价高：800ms 防抖合并，退出时 flushInk 兜底
  private saveInk(): void {
    if (this.inkSaveTimer >= 0) {
      return;
    }
    this.inkSaveTimer = setTimeout((): void => {
      this.inkSaveTimer = -1;
      this.flushInk();
    }, 800);
  }

  private flushInk(): void {
    if (this.inkSaveTimer >= 0) {
      clearTimeout(this.inkSaveTimer);
      this.inkSaveTimer = -1;
    }
    writeJsonFile(`${this.filesDir()}/ink_${this.inkKey}.json`, strokesToJson(this.inkStore.all()));
  }

  // ---------- 草稿持久化 ----------
  private loadDraft(): void {
    const obj = readJsonFile<Record<string, Object>>(`${this.filesDir()}/draft_${this.inkKey}.json`);
    if (obj === null) {
      return;
    }
    this.draftAnchor = obj['anchor'] as number;
    this.draftEnd = obj['end'] as number;
    const rawStrokes = obj['strokes'] as string;
    if (rawStrokes !== undefined && rawStrokes.trim() !== '') {
      try {
        this.draftStore.loadFrom(strokesFromJson(rawStrokes));
      } catch (err) {
        // 历史草稿损坏即弃用，不阻塞开书
      }
    }
  }

  private saveDraft(): void {
    const obj: Record<string, Object> = {
      'anchor': this.draftAnchor,
      'end': this.draftEnd,
      'strokes': strokesToJson(this.draftStore.all())
    };
    writeJsonFile(`${this.filesDir()}/draft_${this.inkKey}.json`, JSON.stringify(obj));
  }

  // ---------- 复习卡持久化 ----------
  private loadReview(): void {
    const arr = readJsonFile<Array<QuizCard>>(`${this.filesDir()}/review.json`);
    if (arr !== null) {
      this.reviewQueue.load(arr);
    }
  }

  private saveReview(): void {
    writeJsonFile(`${this.filesDir()}/review.json`, JSON.stringify(this.reviewQueue.all()));
  }

  // ---------- OCR 页文本缓存 ----------
  private loadOcr(): void {
    const arr = readJsonFile<Array<OcrRecord>>(`${this.filesDir()}/ocr_${this.inkKey}.json`);
    if (arr !== null) {
      this.ocrTexts.load(arr);
    }
  }

  private saveOcr(): void {
    writeJsonFile(`${this.filesDir()}/ocr_${this.inkKey}.json`, JSON.stringify(this.ocrTexts.all()));
  }

  // ---------- 建书索引 ----------
  private async buildIndex(): Promise<void> {
    if (this.indexBuilding || this.indexReady) {
      return;
    }
    this.indexBuilding = true;
    try {
      await this.buildIndexCore();
    } finally {
      this.indexBuilding = false;
    }
  }

  // T3 入口：扫描书按需全书 OCR（按钮即授权），文字层书零 OCR 直建
  private async runOcrIndex(): Promise<void> {
    if (this.indexBuilding) {
      return;
    }
    this.indexBuilding = true;
    try {
      const n = this.source.pageCount();
      const vision = new VisionClient(this.byok.visionBaseUrl, this.byok.apiKey, this.byok.visionModel);
      const indexer = new BookIndexer();
      if (vision.available()) {
        // 付费 OCR 逐批落盘：进程被杀最多丢最后一批，已转录页不重复计费
        let lastSaved = 0;
        await indexer.ensureOcr(this.source, this.ocrTexts, vision, n, this.indexCap,
          (done: number, total: number): void => {
            this.indexStatus = `OCR ${done}/${total}`;
            if (done - lastSaved >= 5) {
              lastSaved = done;
              this.saveOcr();
            }
          });
        this.saveOcr();
      }
      this.indexStatus = '建索引…';
      const r = await this.buildIndexCore();
      this.indexStatus = this.indexReady ? '' : (r.configError ? 'embedding 维度不符（检查模型）' : '索引失败（检查网络/配置）');
    } finally {
      this.indexBuilding = false;
    }
  }

  private async buildIndexCore(): Promise<BuildResult> {
    const n = this.source.pageCount();
    const embed = new EmbeddingClient(this.byok.embedBaseUrl, this.byok.apiKey, this.byok.embedModel);
    const ctx = getContext(this) as common.UIAbilityContext;
    const indexer = new BookIndexer();
    const cache = new IndexCache(ctx.filesDir + '/index', this.inkKey);
    const result = await indexer.build(this.source, n, this.indexCap, embed, cache,
      (_done: number, _total: number): void => {
      }, this.ocrTexts);
    this.indexedChunks = result.chunks;
    this.lexical = result.lexical;
    this.vector = result.vector;
    this.indexReady = result.chunks.length > 0;
    KnowledgeBase.shared().register({
      bookKey: this.inkKey,
      bookTitle: this.bookTitle === '' ? '未命名' : this.bookTitle,
      lexical: result.lexical,
      chunks: result.chunks
    });
    hilog.info(0x0000, 'ReaderView',
      `index built: chunks=${result.chunks.length} embedded=${result.embeddedCount}`);
    return result;
  }

  // 渐进扩展：+INDEX_BATCH 页，重新分析裁边并续跑 OCR/索引
  private async extendIndex(): Promise<void> {
    if (this.indexBuilding || this.analyzing) {
      return;
    }
    this.indexBuilding = true;
    try {
      const n = this.source.pageCount();
      const oldCap = this.indexCap;
      this.indexCap = extendCap(this.indexCap, n, INDEX_BATCH);
      this.saveProgress();
      this.indexStatus = '分析新页…';
      await this.extendAnalysis(oldCap, this.indexCap);
      const vision = new VisionClient(this.byok.visionBaseUrl, this.byok.apiKey, this.byok.visionModel);
      const indexer = new BookIndexer();
      if (vision.available()) {
        this.indexStatus = 'OCR 新页…';
        await indexer.ensureOcr(this.source, this.ocrTexts, vision, n, this.indexCap,
          (done: number, total: number): void => {
            this.indexStatus = `OCR ${done}/${total}`;
          });
        this.saveOcr();
      }
      this.indexStatus = '建索引…';
      this.indexReady = false;
      const r = await this.buildIndexCore();
      this.indexStatus = r.configError ? 'embedding 维度不符（检查模型）' : '';
    } finally {
      this.indexBuilding = false;
    }
  }

  private async extendAnalysis(from: number, to: number): Promise<void> {
    for (let i = from; i < to && i < this.sampleGrids.length; i++) {
      try {
        const sample = await this.source.sampleGray(i, MAX_SAMPLES);
        if (sample === null) {
          this.pageScans[i] = { box: null, spread: false, ink: 0 };
          this.sampleGrids[i] = (this.probeGrid !== null) ? this.probeGrid
            : downsampleGrid(594, 840, MAX_SAMPLES);
          continue;
        }
        this.sampleGrids[i] = sample.grid;
        this.pageScans[i] = scanPage(sample.gray, sample.grid.cols, sample.grid.rows, CROP_DEFAULTS);
      } catch (err) {
        // 单页渲染抛错不拖垮整批扩展（pdfService 偶发 62980109）
        this.pageScans[i] = { box: null, spread: false, ink: 0 };
        hilog.error(0x0000, 'ReaderView', `extendAnalysis page ${i} failed: ${err}`);
      }
    }
    // 扩页后重估一次全书框：新页会进入中位数/MAD 统计，
    // 若与已存框不同则更新并落盘（正常书不会变，因为框本来就该一致）
    this.computeBookCrop(to);
    this.rebuildLayout();
  }

  private indexButtonText(): string {
    return indexButtonLabel(this.analysisStatus, this.indexStatus, this.indexReady,
      this.indexCap, this.pageTops.length);
  }

  private liveOffset(): number {
    try {
      return this.scroller.currentOffset().yOffset;
    } catch (err) {
      return this.scrollY;
    }
  }

  // 气泡是覆盖层，必须靠 scrollY 这个 @State 逐帧重算才能跟着内容走。
  // 但**没有气泡时就没有任何理由逐帧写状态**——纯阅读时零状态写入等于零重渲染，
  // 这是「翻起来顺不顺」的关键。所以气泡一出现就先把位置补正一次。
  private trackScrollForBubbles(): void {
    if (this.bubbles.length > 0) {
      this.scrollY = this.liveOffset();
    }
  }

  private clampAimPage(): number {
    const vp = this.viewportHeight > 0 ? this.viewportHeight : 600;
    return pageAt(this.pageTops, this.liveOffset() + vp / 2);
  }

  private confirmClamp(): void {
    const aim = this.clampAimPage();
    const idx = chapterAt(this.chapters, aim);
    if (idx >= 0) {
      this.applyChapters(split(this.chapters, idx, aim));
    }
    this.clampMode = false;
  }

  private shownBubbles(): Array<QuestionBubble> {
    return foldBubbles(this.bubbles, 5).shown;
  }

  private bubbleViewportY(b: QuestionBubble): number {
    if (b.pageIndex < 0 || b.pageIndex >= this.pageTops.length) {
      return -1;
    }
    const rows = this.sampleGrids[b.pageIndex].rows;
    return bubbleScreenY(this.pageTops[b.pageIndex], this.slotHeights[b.pageIndex], rows,
      b.anchorY, this.scrollY, this.viewportHeight);
  }

  private dotSize(b: QuestionBubble): number {
    return bubbleDotSize(b.phase);
  }

  // 气泡输入草稿（每个气泡独立，互不串扰）
  private bubbleInput(b: QuestionBubble): string {
    const v = this.bubbleInputs.get(b.id);
    return v === undefined ? '' : v;
  }

  private dotOpacity(b: QuestionBubble): number {
    return bubbleDotOpacity(b.phase);
  }


  // ---- CanvasScroll ----
  @Builder
  CanvasScroll() {
    Scroll(this.scroller) {
      Column() {
        ForEach(this.visibleChunks, (ch: PageChunk) => {
          // 窗口外块渲染为等高空占位：撑起整卷高度让长卷可滚（无绘制内容不触发纹理上限）
          Stack() {
            if (ch.pages.length > 0) {
              ForEach(ch.pages, (i: number) => {
                Stack() {
                  if (this.pageImages[i] !== null) {
                    Image(this.pageImages[i]!)
                      .width('100%')
                      .height(this.slotHeights[i])
                      .position({ x: 0, y: this.pageTops[i] - ch.top })
                  }
                  if (this.highlightPage === i) {
                    Rect({ width: this.viewWidth - 8, height: this.slotHeights[i] })
                      .radius(6)
                      .fill('#FF8A2A22')
                      .position({ x: 4, y: this.pageTops[i] - ch.top })
                  }
                  PageInkCanvas({
                    pageIndex: i,
                    slotWidth: this.viewWidth,
                    slotHeight: this.slotHeights[i],
                    penMode: this.penMode,
                    revision: this.inkRevision,
                    store: this.inkStore,
                    pageTransform: this.transforms[i],
                    onGestureArea: (p: number, b: BBox): void => {
                      this.onGesture(p, b);
                    },
                    onStrokeAdded: (): void => {
                      this.saveInk();
                    }
                  })
                    .width('100%')
                    .height(this.slotHeights[i])
                    .position({ x: 0, y: this.pageTops[i] - ch.top })
                }
              }, (i: number) => `page_${i}_${this.pageImages[i] !== null ? 1 : 0}`)
            }
          }
          .width('100%')
          .height(ch.height)
        }, (ch: PageChunk) => `chunk_${ch.top}_${ch.pages.length}_${ch.imgKey}`)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewWidth = Number(newArea.width);
      this.viewportHeight = Number(newArea.height);
      this.rebuildLayout();
    })
    .onScroll((_xOffset: number, yOffset: number) => {
      // 铁律见 pdf/RenderWindow.absoluteScrollOffset：onScroll 的入参是**增量**，
      // 绝对位置只能问滚动容器本身。曾经直接用 yOffset，导致整卷只有第一块有内容。
      const y = absoluteScrollOffset(this.liveOffset(), this.scrollY, yOffset);
      this.refreshWindow(y);
      // 进度节流落盘：每前进 5 页写一次，杀进程最多丢 5 页水位
      if (this.highWaterPage - this.lastSavedWater >= 5) {
        this.lastSavedWater = this.highWaterPage;
        this.saveProgress();
      }
    })
  }

  // ---- LoadingLayer ----
  @Builder
  LoadingLayer() {
    // 加载中 / 打不开：夜城品牌状态层（黑猫 + 一句话 + 行动点），覆盖内容区
    if (this.loadPhase !== 1) {
      Column() {
        if (this.loadPhase === 2) {
          Image($r('app.media.cat'))
            .width(96)
            .height(96)
          Text(this.failInfo.title)
            .fontColor('#F7F0E4')
            .fontSize(17)
            .margin({ top: 20 })
          Text(this.failInfo.hint)
            .fontColor('#8CA2C0')
            .fontSize(12)
            .margin({ top: 8 })
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })
          // 只有成因不是「文件没了/要密码」时才给重试：否则点了也是白点
          if (this.failInfo.canRetry) {
            Text('重试')
              .fontColor('#060B12')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 26, right: 26, top: 11, bottom: 11 })
              .borderRadius(12)
              .backgroundColor('#FF8A2A')
              .shadow({ radius: 0, color: '#060B12', offsetX: 3, offsetY: 4 })
              .margin({ top: 24 })
              .onClick(() => {
                this.loadPhase = 0;
                this.prepare();
              })
          }
          Text('点左上角返回书房')
            .fontColor('#5C7396')
            .fontSize(11)
            .margin({ top: 16 })
        } else {
          Image($r('app.media.cat'))
            .width(72)
            .height(72)
            .opacity(0.9)
          Text('正在打开…')
            .fontColor('#8CA2C0')
            .fontSize(13)
            .margin({ top: 14 })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#101E33')
    }
  }

  // ---- BubbleLayer ----
  @Builder
  BubbleLayer() {
    ForEach(this.shownBubbles(), (b: QuestionBubble) => {
      if (this.bubbleViewportY(b) >= 0) {
        Circle({ width: this.dotSize(b), height: this.dotSize(b) })
          .fill('#FF8A2A')
          .opacity(this.dotOpacity(b))
          .scale({
            x: b.phase === BubblePhase.Thinking ? (this.breatheOut ? 1.08 : 1) : 1,
            y: b.phase === BubblePhase.Thinking ? (this.breatheOut ? 1.08 : 1) : 1
          })
          // 呼吸动画挂在气泡自己身上（原先是根 Stack 上的无限动画）
          .animation({ duration: 2500, curve: Curve.EaseInOut })
          .position({ x: 4, y: this.bubbleViewportY(b) - this.dotSize(b) / 2 })
          .onClick(() => {
            this.onBubbleTap(b);
          })
        if (this.expandedBubbleId === b.id) {
          Column() {
            Text(`P${b.pageIndex + 1} · 圈选提问`)
              .fontColor('#FF8A2A')
              .fontSize(13)
            if (this.byok.apiKey === '' || this.showConfig) {
              if (this.showConfig) {
                Text('修改 BYOK 配置')
                  .fontColor('#FF8A2A')
                  .fontSize(12)
                  .margin({ top: 2 })
                  .onClick(() => {
                    this.showConfig = false;
                  })
              }
              Text('配置 BYOK（OpenAI 兼容接口）')
                .fontColor('#8CA2C0')
                .fontSize(12)
                .margin({ top: 6 })
              TextInput({ placeholder: 'Base URL', text: this.inputBaseUrl })
                .fontSize(12)
                .height(36)
                .margin({ top: 6 })
                .onChange((v: string) => {
                  this.inputBaseUrl = v;
                })
              TextInput({ placeholder: 'API Key', text: this.inputApiKey })
                .fontSize(12)
                .height(36)
                .type(InputType.Password)
                .margin({ top: 6 })
                .onChange((v: string) => {
                  this.inputApiKey = v;
                })
              TextInput({ placeholder: 'Chat 模型（如 deepseek-chat / qwen-plus）', text: this.inputModel })
                .fontSize(12)
                .height(36)
                .margin({ top: 4 })
                .onChange((v: string) => {
                  this.inputModel = v;
                })
              Text('Embedding（可选，如 SiliconFlow bge-m3）')
                .fontColor('#5C7396')
                .fontSize(11)
                .margin({ top: 6 })
              TextInput({ placeholder: 'Embedding Base URL', text: this.inputEmbedBase })
                .fontSize(12)
                .height(36)
                .margin({ top: 4 })
                .onChange((v: string) => {
                  this.inputEmbedBase = v;
                })
              TextInput({ placeholder: 'Embedding 模型', text: this.inputEmbedModel })
                .fontSize(12)
                .height(36)
                .margin({ top: 4 })
                .onChange((v: string) => {
                  this.inputEmbedModel = v;
                })
              Text('Vision（可选，扫描书圈选OCR，如 Qwen2.5-VL）')
                .fontColor('#5C7396')
                .fontSize(11)
                .margin({ top: 6 })
              TextInput({ placeholder: 'Vision Base URL', text: this.inputVisionBase })
                .fontSize(12)
                .height(36)
                .margin({ top: 4 })
                .onChange((v: string) => {
                  this.inputVisionBase = v;
                })
              TextInput({ placeholder: 'Vision 模型', text: this.inputVisionModel })
                .fontSize(12)
                .height(36)
                .margin({ top: 4 })
                .onChange((v: string) => {
                  this.inputVisionModel = v;
                })
              Row() {
                Text('跨书引用（统一知识库）')
                  .fontColor('#8CA2C0')
                  .fontSize(11)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Checkbox, isOn: this.byok.crossBook })
                  .onChange((on: boolean) => {
                    this.byok.crossBook = on;
                    this.byokStore.save(getContext(this) as common.UIAbilityContext, this.byok);
                  })
              }
              .width('100%')
              .margin({ top: 6 })
              Button('保存并就绪')
                .fontSize(13)
                .height(32)
                .width('100%')
                .margin({ top: 8 })
                .backgroundColor('#FF8A2A')
                .onClick(() => {
                  const cfg: ByokConfig = {
                    baseUrl: this.inputBaseUrl,
                    apiKey: this.inputApiKey,
                    model: this.inputModel,
                    embedBaseUrl: this.inputEmbedBase,
                    embedModel: this.inputEmbedModel,
                    visionBaseUrl: this.inputVisionBase,
                    visionModel: this.inputVisionModel,
                    crossBook: this.byok.crossBook,
                    crossNoticeShown: this.byok.crossNoticeShown
                  };
                  this.byok = cfg;
                  this.byokStore.save(getContext(this) as common.UIAbilityContext, cfg);
                })
            } else if (this.cardPhaseOf(b.id) === 1) {
              Text('思考中…')
                .fontColor('#FF8A2A')
                .fontSize(13)
                .margin({ top: 6 })
            } else if (this.cardPhaseOf(b.id) === 2) {
              if (this.cardNoticeOf(b.id) !== '') {
                Text(this.cardNoticeOf(b.id))
                  .fontColor('#FF8A2A')
                  .fontSize(11)
                  .margin({ top: 4 })
              }
              Text(this.cardAnswerOf(b.id))
                .fontColor('#F7F0E4')
                .fontSize(13)
                .margin({ top: 6 })
              if (this.cardRefPagesOf(b.id).length > 0) {
                Row({ space: 6 }) {
                  Text('来源：')
                    .fontColor('#8CA2C0')
                    .fontSize(11)
                  ForEach(this.cardRefPagesOf(b.id), (pg: number) => {
                    Text(`P${pg + 1}`)
                      .fontColor('#FF8A2A')
                      .fontSize(11)
                      .onClick(() => {
                        this.jumpToPage(pg);
                      })
                  }, (pg: number) => `ref_${pg}`)
                }
                .margin({ top: 6 })
              }
              if (this.cardRelatedPagesOf(b.id).length > 0) {
                Row({ space: 6 }) {
                  Text('相关位置：')
                    .fontColor('#8CA2C0')
                    .fontSize(11)
                  ForEach(this.cardRelatedPagesOf(b.id), (pg: number) => {
                    Text(`P${pg + 1}`)
                      .fontColor('#FF8A2A')
                      .fontSize(11)
                      .opacity(0.75)
                      .onClick(() => {
                        this.jumpToPage(pg);
                      })
                  }, (pg: number) => `rel_${pg}`)
                }
                .margin({ top: 4 })
              }
              Text('修改 BYOK 配置 →')
                .fontColor('#8CA2C0')
                .fontSize(11)
                .margin({ top: 6 })
                .onClick(() => {
                  this.showConfig = true;
                })
            } else {
              Text('正在准备提问…')
                .fontColor('#8CA2C0')
                .fontSize(12)
                .margin({ top: 6 })
            }
            Row({ space: 6 }) {
              TextInput({ placeholder: '输入你的问题…', text: this.bubbleInput(b) })
                .fontSize(12)
                .height(32)
                .layoutWeight(1)
                .onChange((v: string) => {
                  this.bubbleInputs.set(b.id, v);
                })
              Button('问')
                .fontSize(12)
                .height(32)
                .backgroundColor('#FF8A2A')
                .onClick(() => {
                  this.sendQuestion(b);
                })
            }
            .margin({ top: 8 })
          }
          .padding(12)
          .borderRadius(10)
          .backgroundColor('#182A47')
          .width(300)
          .alignItems(HorizontalAlign.Start)
          .position({ x: 28, y: this.bubbleViewportY(b) - 20 })
          .onClick(() => {
            this.expandedBubbleId = -1;
          })
        }
      }
    }, (b: QuestionBubble) => `bubble_${b.id}_${b.phase}`)
  }

  // ---- BubblePins ----
  @Builder
  BubblePins() {
    // 滚出视野的气泡缩成图钉（点击跳回所在页）
    ForEach(this.shownBubbles(), (b: QuestionBubble, idx: number) => {
      if (this.bubbleViewportY(b) < 0) {
        Circle({ width: 6, height: 6 })
          .fill('#FF8A2A')
          .opacity(0.7)
          .position({ x: 6, y: 60 + idx * 16 })
          .onClick(() => {
            this.jumpToPage(b.pageIndex);
          })
      }
    }, (b: QuestionBubble, idx: number) => `pin_${b.id}_${idx}`)
  }

  // ---- BubbleFoldBadge ----
  @Builder
  BubbleFoldBadge() {
    if (foldBubbles(this.bubbles, 5).extraCount > 0) {
      Text(`+${foldBubbles(this.bubbles, 5).extraCount}`)
        .fontColor('#FF8A2A')
        .fontSize(11)
        .position({ x: 2, y: 52 })
    }
  }

  // ---- ClampLayer ----
  @Builder
  ClampLayer() {
    // 夹页模式：虚线固定视口中央，上下滑动对准章末，确认即在当前章内拆分
    if (this.clampMode) {
      Column()
        .width('100%')
        .height(0)
        .border({ width: 2, color: '#FF8A2A', style: BorderStyle.Dashed })
        .position({ x: 0, y: (this.viewportHeight > 0 ? this.viewportHeight : 600) / 2 })
      Text(`对准 P${this.clampAimPage() + 1}`)
        .fontColor('#FF8A2A')
        .fontSize(13)
        .position({
          x: this.viewWidth > 0 ? this.viewWidth - 90 : 300,
          y: (this.viewportHeight > 0 ? this.viewportHeight : 600) / 2 - 26
        })
      Column() {
        Text('上下滑动，把虚线对准章末')
          .fontColor('#B9C7DC')
          .fontSize(12)
        Row({ space: 8 }) {
          Button('取消')
            .fontSize(12)
            .height(30)
            .backgroundColor('#182A47')
            .onClick(() => {
              this.clampMode = false;
            })
          Button('确认夹入')
            .fontSize(12)
            .height(30)
            .backgroundColor('#FF8A2A')
            .onClick(() => {
              this.confirmClamp();
            })
        }
      }
      .width('100%')
      .padding(10)
      .backgroundColor('rgba(10,18,32,0.95)')
      .alignItems(HorizontalAlign.Center)
      .position({
        x: 0,
        y: (this.viewportHeight > 0 ? this.viewportHeight : 600) - 86
      })
    }
  }

  // ---- EdgeGestureStrip ----
  @Builder
  EdgeGestureStrip() {
    // 左缘手势条：左滑掀纸进草稿（避开画笔层的独立命中区）
    if (!this.draftOpen) {
      Column()
        .width(EDGE_STRIP_W)
        .height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 40 })
          .onActionEnd((e: GestureEvent) => {
            if (isLeftSwipe(e.offsetX, e.offsetY, SWIPE_THRESHOLD)) {
              if (this.draftAnchor < 0) {
                this.draftAnchor = this.readerPage;
                this.draftEnd = this.readerPage;
              }
              this.draftOpen = true;
            }
          }))
        .position({ x: 0, y: 0 })
    }
  }

  // ---- DraftBookmark ----
  @Builder
  DraftBookmark() {
    // 草稿书签（右缘）：草稿范围覆盖当前页时出现
    if (!this.draftOpen && this.draftAnchor >= 0 && this.readerPage >= this.draftAnchor
      && this.readerPage <= this.draftEnd) {
      Button('草')
        .fontSize(12)
        .width(26)
        .height(56)
        .type(ButtonType.Capsule)
        .backgroundColor('#FF8A2A66')
        .fontColor('#F7F0E4')
        .position({ x: this.viewWidth > 0 ? this.viewWidth - 24 : 380, y: 140 })
        .onClick(() => {
          this.draftOpen = true;
        })
    }
  }

  // ---- ChapterPanel ----
  @Builder
  ChapterPanel() {
    // 分章夹子面板
    if (this.chapterPanelOpen) {
      Column() {
        Row() {
          Column() {
            Text('分章夹子')
              .fontColor('#F7F0E4')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
            if (this.chapters.length <= 1) {
              Text('要不要先夹一章？跳过也不影响任何功能')
                .fontColor('#8CA2C0')
                .fontSize(11)
                .margin({ top: 2 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Blank()
          Button('收起')
            .fontSize(12)
            .height(26)
            .backgroundColor('#182A47')
            .onClick(() => {
              this.chapterPanelOpen = false;
            })
        }
        .width('100%')
        if (this.chapters.length <= 1) {
          Button('识章（扫描书：视觉读目录页）')
            .fontSize(12)
            .height(28)
            .width('100%')
            .backgroundColor('#FF8A2A')
            .margin({ top: 6 })
            .onClick(() => {
              this.recognizeToc();
            })
        }
        Button('夹页（新开一章）')
          .fontSize(12)
          .height(28)
          .width('100%')
          .backgroundColor('#182A47')
          .margin({ top: 6 })
          .onClick(() => {
            this.chapterPanelOpen = false;
            this.clampMode = true;
          })
        if (this.renameIdx >= 0) {
          Row({ space: 6 }) {
            TextInput({ text: this.renameInput })
              .fontSize(12)
              .height(32)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.renameInput = v;
              })
            Button('定名')
              .fontSize(12)
              .height(32)
              .backgroundColor('#FF8A2A')
              .onClick(() => {
                this.applyChapters(rename(this.chapters, this.renameIdx, this.renameInput));
                this.renameIdx = -1;
              })
          }
          .width('100%')
          .margin({ top: 8 })
        }
        List({ space: 4 }) {
          ForEach(this.chapters, (c: Chapter, idx: number) => {
            ListItem() {
              Row() {
                Text(`${c.title}  P${c.firstPage + 1}-${c.lastPage + 1}`)
                  .fontColor('#DCE6F5')
                  .fontSize(12)
                  .maxLines(1)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.renameIdx = idx;
                    this.renameInput = c.title;
                  })
                Button('拆')
                  .fontSize(11)
                  .height(24)
                  .backgroundColor('#182A47')
                  .onClick(() => {
                    const at = (this.readerPage > c.firstPage && this.readerPage <= c.lastPage)
                      ? this.readerPage : c.firstPage + 1;
                    this.applyChapters(split(this.chapters, idx, at));
                  })
                Button('合')
                  .fontSize(11)
                  .height(24)
                  .backgroundColor('#182A47')
                  .margin({ left: 4 })
                  .onClick(() => {
                    this.applyChapters(mergeNext(this.chapters, idx));
                  })
                if (idx > 0) {
                  Button('缝')
                    .fontSize(11)
                    .height(24)
                    .backgroundColor('#182A47')
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.applyChapters(moveBoundary(this.chapters, idx, this.readerPage));
                    })
                }
              }
              .width('100%')
              .padding(6)
              .borderRadius(6)
              .backgroundColor('#23395C')
            }
          }, (c: Chapter, idx: number) => `ch_${idx}_${c.firstPage}_${c.lastPage}`)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 8 })
      }
      .padding(12)
      .borderRadius(12)
      .backgroundColor('#182A47')
      .width('86%')
      .height('62%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // ---- DraftPage ----
  @Builder
  DraftPage() {
    // 草稿页（v1：单张长画布 + 范围延伸）
    if (this.draftOpen) {
      Column() {
        Row({ space: 8 }) {
          Text(this.draftAnchor >= 0
            ? `草稿 · 范围P${this.draftAnchor + 1}-${this.draftEnd + 1}` : '草稿')
            .fontColor('#F7F0E4')
            .fontSize(13)
          Blank()
          Button('+1页')
            .fontSize(12)
            .height(26)
            .backgroundColor('#182A47')
            .onClick(() => {
              this.draftEnd += 1;
              this.saveDraft();
            })
          Button('完成')
            .fontSize(12)
            .height(26)
            .backgroundColor('#FF8A2A')
            .onClick(() => {
              this.saveDraft();
              this.draftOpen = false;
            })
        }
        .width('100%')
        .height(34)
        .padding({ left: 10, right: 10 })

        Stack() {
          // 草稿纸面：黑墨需要纸底（预览核验发现的对比度缺陷）
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#F7F5F0')
          PageInkCanvas({
            pageIndex: 0,
            slotWidth: this.viewWidth > 0 ? this.viewWidth : 400,
            slotHeight: DRAFT_CANVAS_H,
            penMode: this.penMode,
            store: this.draftStore,
            pageTransform: {
              scale: 1,
              offsetX: 0,
              offsetY: 0,
              contentHeight: DRAFT_CANVAS_H
            },
            onGestureArea: (_p: number, _b: BBox): void => {
            },
            onStrokeAdded: (): void => {
              this.saveDraft();
            }
          })
            .width('100%')
            .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#101E33')
    }
  }

  // ---- BottomToolbar ----
  @Builder
  BottomToolbar() {
    // 工具栏贴底：Stack 子组件默认居中会把工具栏悬在屏幕正中——
    // 包一层全高透明容器， justifyContent End 落底，空白区放行触摸给长卷
    Column() {
      Row() {
        Text(`${this.chapterTitle} · P${this.highWaterPage + 1}`)
          .fontColor('#8CA2C0')
          .fontSize(12)
      Button('−')
        .fontSize(11)
        .width(22)
        .height(22)
        .padding(0)
        .backgroundColor('#182A47')
        .margin({ left: 6 })
        .onClick(() => {
          this.highWaterPage = Math.max(0, this.highWaterPage - 1);
          this.saveProgress();
        })
      Button('+')
        .fontSize(11)
        .width(22)
        .height(22)
        .padding(0)
        .backgroundColor('#182A47')
        .margin({ left: 2 })
        .onClick(() => {
          this.highWaterPage = Math.min(this.pageTops.length - 1, this.highWaterPage + 1);
          this.saveProgress();
        })
      Button(this.wholeBook ? '全书' : '已读')
        .fontSize(11)
        .height(22)
        .padding({ left: 6, right: 6 })
        .backgroundColor(this.wholeBook ? '#FF8A2A' : '#182A47')
        .fontColor('#F7F0E4')
        .margin({ left: 6 })
        .onClick(() => {
          this.wholeBook = !this.wholeBook;
        })
      if (this.questionCount > 0) {
        Text(`问 ${this.questionCount}`)
          .fontColor('#FF8A2A')
          .fontSize(12)
          .margin({ left: 6 })
      }
      Blank()
      Button(this.indexButtonText())
        .fontSize(this.indexStatus === '' ? 13 : 11)
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor('#22395F')
        .fontColor(this.indexReady ? '#F7F0E4' : '#FF8A2A')
        .opacity(this.indexBuilding ? 0.6 : 1)
        .onClick(() => {
          if (this.indexReady && this.indexCap < this.pageTops.length) {
            this.extendIndex();
          } else {
            this.runOcrIndex();
          }
        })
      Button('草')
        .fontSize(15)
        .height(34)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.draftOpen ? '#FF8A2A' : '#22395F')
        .fontColor(this.draftOpen ? '#060B12' : '#F7F0E4')
        .onClick(() => {
          if (this.draftAnchor < 0) {
            this.draftAnchor = this.readerPage;
            this.draftEnd = this.readerPage;
          }
          this.draftOpen = true;
        })
      Button('夹')
        .fontSize(15)
        .height(34)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.chapterPanelOpen ? '#FF8A2A' : '#22395F')
        .fontColor(this.chapterPanelOpen ? '#060B12' : '#F7F0E4')
        .margin({ left: 6 })
        .onClick(() => {
          this.chapterPanelOpen = !this.chapterPanelOpen;
        })
      Button('撤')
        .fontSize(15)
        .width(40)
        .height(34)
        .backgroundColor('#22395F')
        .fontColor('#F7F0E4')
        .onClick(() => {
          // 撤销最后书写的一笔（按笔画自身所在页，而非当前停留页——滚动后撤的才是刚写的）
          const all = this.inkStore.all();
          const lastStroke = all[all.length - 1];
          this.inkStore.removeLast(lastStroke !== undefined ? lastStroke.pageIndex : this.readerPage);
          this.inkRevision++;
          this.saveInk();
        })
      Button('墨')
        .fontSize(15)
        .width(40)
        .height(34)
        .backgroundColor(this.penMode === PEN_INK ? '#34527D' : '#22395F')
        .fontColor('#F7F0E4')
        .margin({ left: 6 })
        .onClick(() => {
          this.penMode = PEN_INK;
        })
      Button('问')
        .fontSize(15)
        .width(40)
        .height(34)
        .backgroundColor(this.penMode === PEN_AI ? '#FF8A2A' : '#22395F')
        .fontColor(this.penMode === PEN_AI ? '#060B12' : '#F7F0E4')
        .margin({ left: 4 })
        .onClick(() => {
          this.penMode = PEN_AI;
        })
    }
      .width('100%')
      .height(46)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#101E33F0')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    Stack() {
      this.CanvasScroll()

      this.LoadingLayer()

      this.BubbleLayer()

      this.BubblePins()

      this.BubbleFoldBadge()

      this.ClampLayer()

      this.EdgeGestureStrip()

      this.DraftBookmark()

      this.ChapterPanel()

      this.DraftPage()

      this.BottomToolbar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#101E33')
    // 这里**不能**放 animateTo({ iterations: -1 })：根级无限动画会让整棵树每帧重渲染
    //（一整棵含 24 页槽位的树），是持续卡顿的来源。气泡呼吸见 syncBreathe()。
  }
}
