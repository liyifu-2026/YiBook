import { InstantShapeGenerator, ShapeInfo } from '@kit.Penkit';
import { strokeBBox, mapShapeToGesture, GestureKind, InkPoint } from './GestureMath';
import { toPagePoint } from '../pdf/ReaderGeometry';
import { InkStroke, InkStore } from './InkStore';
import { DisplayTransform } from '../pdf/ReaderGeometry';
import { BBox } from '../pdf/CropMath';

// 单页墨迹层：叠在该页渲染图上的透明画布。
// 普通笔 = 黑墨；AI 笔 = 液态彩半透明，抬笔交给系统一笔成形，
// 圈/框（词表内）规整化并上报区域，其余形状按普通墨迹保留。
const LIQUID_COLOR = '#0A84FF';
const INK_COLOR = '#161616';

// 运行时的 TouchObject 带 sourceTool（编译器声明滞后，只在 BaseEvent 上有）：
// 触摸级优先，取不到退回事件级。手指/触控笔区分是书写硬性条件。
interface PenTouchObject extends TouchObject {
  sourceTool?: SourceTool;
}

@Component
export struct PageInkCanvas {
  @Prop pageIndex: number = 0;
  @Prop slotWidth: number = 0;
  @Prop slotHeight: number = 0;
  @Prop penMode: number = 0; // 0=不可画 1=普通墨迹 2=AI笔
  @Prop @Watch('onRevisionChange') revision: number = 0;
  store: InkStore = new InkStore();
  pageTransform: DisplayTransform = {
    scale: 1,
    offsetX: 0,
    offsetY: 0,
    contentHeight: 0
  };
  onGestureArea: (pageIndex: number, bbox: BBox) => void = (_p: number, _b: BBox) => {
  };
  onStrokeAdded: () => void = () => {
  };

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private activePoints: Array<InkPoint> = []; // 槽位坐标；Up 后保留等待系统识别回调
  private drawing: boolean = false;
  private shapeGen: InstantShapeGenerator = new InstantShapeGenerator();

  aboutToAppear(): void {
    this.shapeGen.onShapeRecognized((info: ShapeInfo): void => {
      this.onShape(info);
    });
  }

  onRevisionChange(): void {
    this.redraw();
  }

  aboutToDisappear(): void {
    this.shapeGen.release();
  }

  private onShape(info: ShapeInfo): void {
    if (this.activePoints.length === 0) {
      return;
    }
    const bbox = strokeBBox(this.activePoints);
    if (bbox !== null && mapShapeToGesture(info.shapeType, bbox) === GestureKind.Question) {
      const strokes = this.store.strokesOf(this.pageIndex);
      const last = strokes[strokes.length - 1];
      if (last !== undefined && last.isAi && !last.regularized) {
        last.regularized = true;
        last.shapeString = info.shapeString;
        // shapeString 是槽位局部坐标：记录落笔时的变换，绘制时映射回当前槽位（铁律3）
        last.capScale = this.pageTransform.scale;
        last.capOffX = this.pageTransform.offsetX;
        last.capOffY = this.pageTransform.offsetY;
      }
      const topLeft = toPagePoint(this.pageTransform, bbox.left, bbox.top);
      const bottomRight = toPagePoint(this.pageTransform, bbox.right, bbox.bottom);
      const pageBox: BBox = {
        left: topLeft.x,
        top: topLeft.y,
        right: bottomRight.x,
        bottom: bottomRight.y
      };
      this.onGestureArea(this.pageIndex, pageBox);
      this.onStrokeAdded();
    }
    this.activePoints = [];
  }

  private handleTouch(event: TouchEvent): void {
    if (this.penMode === 0) {
      return;
    }
    const isAi = this.penMode === 2;
    const touches = event.changedTouches;
    for (let i = 0; i < touches.length; i++) {
      // 硬性条件：手指永远滚动、只有触控笔才书写（用户定调，无可妥协）。
      // 触摸级 sourceTool 取不到时退回事件级；两者都不是 Pen 的触点直接忽略、不挡滚动手势。
      const pt = touches[i] as PenTouchObject;
      const touchSource = pt.sourceTool !== undefined ? pt.sourceTool : event.sourceTool;
      if (touchSource !== SourceTool.Pen) {
        continue;
      }
      const x = touches[i].x;
      const y = touches[i].y;
      if (event.type === TouchType.Down) {
        this.drawing = true;
        const p: InkPoint = { x: x, y: y };
        this.activePoints = [p];
        if (isAi) {
          this.shapeGen.processTouchEvent(event);
        }
        this.redraw();
      } else if (event.type === TouchType.Move && this.drawing) {
        const p: InkPoint = { x: x, y: y };
        this.activePoints.push(p);
        if (isAi) {
          this.shapeGen.processTouchEvent(event);
        }
        this.redraw();
      } else if (event.type === TouchType.Up && this.drawing) {
        this.drawing = false;
        if (isAi) {
          this.shapeGen.processTouchEvent(event);
        }
        if (this.strokeWorthy()) {
          this.commitStroke(isAi);
          this.redraw();
          this.onStrokeAdded();
        } else {
          this.activePoints = [];
          this.redraw();
        }
      } else if (event.type === TouchType.Cancel && this.drawing) {
        // 滚动/系统手势接管以 Cancel 收尾：丢弃，避免把轨迹的前几个点存成墨迹
        this.drawing = false;
        this.activePoints = [];
        if (isAi) {
          this.shapeGen.processTouchEvent(event);
        }
        this.redraw();
      }
    }
  }

  // 过短的轨迹（滚动被接管前的残尾、误触）不值得成笔
  private strokeWorthy(): boolean {
    if (this.activePoints.length < 3) {
      return false;
    }
    let minX = this.activePoints[0].x;
    let maxX = minX;
    let minY = this.activePoints[0].y;
    let maxY = minY;
    for (const p of this.activePoints) {
      minX = Math.min(minX, p.x);
      maxX = Math.max(maxX, p.x);
      minY = Math.min(minY, p.y);
      maxY = Math.max(maxY, p.y);
    }
    const diag = Math.hypot(maxX - minX, maxY - minY);
    return diag >= 14;
  }

  private commitStroke(isAi: boolean): void {
    const pagePoints: Array<InkPoint> = [];
    for (const p of this.activePoints) {
      const q = toPagePoint(this.pageTransform, p.x, p.y);
      const converted: InkPoint = { x: q.x, y: q.y };
      pagePoints.push(converted);
    }
    const stroke: InkStroke = {
      pageIndex: this.pageIndex,
      pagePoints: pagePoints,
      isAi: isAi,
      regularized: false,
      shapeString: ''
    };
    this.store.add(stroke);
  }

  private redraw(): void {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.slotWidth, this.slotHeight);
    const strokes = this.store.strokesOf(this.pageIndex);
    for (const s of strokes) {
      if (s.regularized && s.shapeString !== '') {
        ctx.save();
        if (s.capScale !== undefined && s.capScale > 0) {
          // 把落笔时的槽位坐标映射到当前槽位：缩放比 + 平移差
          const k = this.pageTransform.scale / s.capScale;
          ctx.translate(this.pageTransform.offsetX - s.capOffX! * k,
            this.pageTransform.offsetY - s.capOffY! * k);
          ctx.scale(k, k);
        }
        const path = this.shapeGen.getPathFromString(s.shapeString, 2.5);
        ctx.strokeStyle = LIQUID_COLOR;
        ctx.globalAlpha = 0.9;
        ctx.lineWidth = 2.5;
        ctx.stroke(path);
        ctx.restore();
      } else {
        this.drawRaw(s.pagePoints, s.isAi);
      }
    }
    if (this.drawing) {
      this.drawActive();
    }
    ctx.globalAlpha = 1;
  }

  private drawActive(): void {
    if (this.activePoints.length === 0) {
      return;
    }
    const ctx = this.ctx;
    ctx.beginPath();
    for (let i = 0; i < this.activePoints.length; i++) {
      if (i === 0) {
        ctx.moveTo(this.activePoints[i].x, this.activePoints[i].y);
      } else {
        ctx.lineTo(this.activePoints[i].x, this.activePoints[i].y);
      }
    }
    ctx.strokeStyle = this.penMode === 2 ? LIQUID_COLOR : INK_COLOR;
    ctx.globalAlpha = this.penMode === 2 ? 0.55 : 0.92;
    ctx.lineWidth = this.penMode === 2 ? 3 : 2.5;
    ctx.stroke();
  }

  private drawRaw(points: Array<InkPoint>, isAi: boolean): void {
    if (points.length === 0) {
      return;
    }
    const ctx = this.ctx;
    ctx.beginPath();
    for (let i = 0; i < points.length; i++) {
      const sx = points[i].x * this.pageTransform.scale + this.pageTransform.offsetX;
      const sy = points[i].y * this.pageTransform.scale + this.pageTransform.offsetY;
      if (i === 0) {
        ctx.moveTo(sx, sy);
      } else {
        ctx.lineTo(sx, sy);
      }
    }
    ctx.strokeStyle = isAi ? LIQUID_COLOR : INK_COLOR;
    ctx.globalAlpha = isAi ? 0.55 : 0.92;
    ctx.lineWidth = isAi ? 3 : 2.5;
    ctx.stroke();
  }

  build() {
    Canvas(this.ctx)
      .width(this.slotWidth)
      .height(this.slotHeight)
      .hitTestBehavior(this.penMode === 0 ? HitTestMode.None : HitTestMode.Default)
      .onReady(() => {
        this.redraw();
      })
      .onTouch((event: TouchEvent) => {
        this.handleTouch(event);
      })
  }
}
