import { InkPoint } from './GestureMath';

export interface InkStroke {
  pageIndex: number;
  // 锚点：原始页坐标（采样栅格系），裁边/换设备都不漂移（铁律3）
  pagePoints: Array<InkPoint>;
  isAi: boolean;
  regularized: boolean;
  // 系统一笔成形的规整路径（槽位局部坐标系字符串），regularized 时有效。
  // 槽位坐标会随裁边/屏宽漂移，故记录落笔时的槽位变换，绘制时映射回当前槽位。
  shapeString: string;
  capScale?: number;
  capOffX?: number;
  capOffY?: number;
}

export class InkStore {
  private byPage: Map<number, Array<InkStroke>> = new Map();

  add(stroke: InkStroke): void {
    let list = this.byPage.get(stroke.pageIndex);
    if (list === undefined) {
      list = [];
      this.byPage.set(stroke.pageIndex, list);
    }
    list.push(stroke);
  }

  strokesOf(pageIndex: number): Array<InkStroke> {
    const list = this.byPage.get(pageIndex);
    if (list === undefined) {
      return [];
    }
    return list;
  }

  all(): Array<InkStroke> {
    const out: Array<InkStroke> = [];
    for (const key of this.byPage.keys()) {
      const list = this.byPage.get(key) as Array<InkStroke>;
      for (const s of list) {
        out.push(s);
      }
    }
    return out;
  }

  loadFrom(strokes: Array<InkStroke>): void {
    this.byPage = new Map();
    for (const s of strokes) {
      this.add(s);
    }
  }

  count(): number {
    return this.all().length;
  }

  // 撤销某页最新一笔（笔迹后悔药）
  removeLast(pageIndex: number): void {
    const list = this.byPage.get(pageIndex);
    if (list !== undefined && list.length > 0) {
      list.pop();
    }
  }
}
