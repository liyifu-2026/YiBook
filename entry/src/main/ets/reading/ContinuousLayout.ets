export function pageOffsets(pageHeights: Array<number>, overlap: number): Array<number> {
  const offsets: Array<number> = [];
  let y = 0;
  for (let i = 0; i < pageHeights.length; i++) {
    offsets.push(y);
    y += pageHeights[i] - overlap;
  }
  return offsets;
}

export function totalHeight(pageHeights: Array<number>, overlap: number): number {
  const n = pageHeights.length;
  if (n === 0) {
    return 0;
  }
  const offsets = pageOffsets(pageHeights, overlap);
  return offsets[n - 1] + pageHeights[n - 1];
}

export function pageAt(offsets: Array<number>, y: number): number {
  const n = offsets.length;
  if (n === 0) {
    return -1;
  }
  if (y <= 0) {
    return 0;
  }
  if (y >= offsets[n - 1]) {
    return n - 1;
  }
  let lo = 0;
  let hi = n - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (offsets[mid] <= y) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}
