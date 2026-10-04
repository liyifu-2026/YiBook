import { pageAt } from './ContinuousLayout';

export interface PageRange {
  first: number;
  last: number;
}

export function renderWindow(offsets: Array<number>, scrollY: number, viewportHeight: number,
  prerender: number): PageRange {
  const n = offsets.length;
  if (n === 0) {
    const empty: PageRange = { first: -1, last: -1 };
    return empty;
  }
  let first = pageAt(offsets, scrollY) - prerender;
  let last = pageAt(offsets, scrollY + viewportHeight) + prerender;
  if (first < 0) {
    first = 0;
  }
  if (last > n - 1) {
    last = n - 1;
  }
  const range: PageRange = { first: first, last: last };
  return range;
}
