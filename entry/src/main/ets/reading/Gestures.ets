// 手势词法（草稿掀纸入口）与渐进上限（全书索引/裁边的批次推进）。
// 左/右滑判定：水平位移过阈值且为垂直位移的 1.5 倍以上（防误触滚动）。

export function isLeftSwipe(dx: number, dy: number, threshold: number): boolean {
  return dx < -threshold && Math.abs(dx) > Math.abs(dy) * 1.5;
}

export function extendCap(current: number, total: number, batch: number): number {
  const step = batch < 1 ? 1 : batch;
  return Math.min(total, current + step);
}
