// 章节骨架：自动分章（PDF 书签）打底，分章夹子只做修正（调研报告决策 #1）。
// 所有操作均为纯函数、拷贝后返回；不变式：按 firstPage 升序、连续覆盖 [0, pageCount-1]。

export interface OutlineMarker {
  title: string;
  page: number;
}

export interface Chapter {
  id: number;
  title: string;
  firstPage: number;
  lastPage: number;
  manual: boolean;
}

function copyWith(chapter: Chapter, title: string, firstPage: number, lastPage: number,
  manual: boolean): Chapter {
  const c: Chapter = {
    id: chapter.id,
    title: title,
    firstPage: firstPage,
    lastPage: lastPage,
    manual: manual
  };
  return c;
}

export function chaptersFromOutline(markers: Array<OutlineMarker>, pageCount: number): Array<Chapter> {
  if (pageCount <= 0) {
    return [];
  }
  const valid = markers.filter(m => m.page >= 0 && m.page < pageCount);
  valid.sort((a, b) => a.page - b.page);
  const unique: Array<OutlineMarker> = [];
  for (const m of valid) {
    if (unique.length === 0 || unique[unique.length - 1].page !== m.page) {
      unique.push(m);
    }
  }
  if (unique.length === 0 || unique.length * 2 > pageCount) {
    // 垃圾书签防御：逐页书签（扫描件常见）密度过高时视为无目录，整本一章
    const whole: Array<Chapter> = [copyWith({
      id: 0,
      title: '',
      firstPage: 0,
      lastPage: 0,
      manual: false
    }, '全书', 0, pageCount - 1, false)];
    return whole;
  }
  const chapters: Array<Chapter> = [];
  let nextId = 0;
  if (unique[0].page > 0) {
    chapters.push(copyWith({
      id: nextId++,
      title: '',
      firstPage: 0,
      lastPage: 0,
      manual: false
    }, '卷首', 0, unique[0].page - 1, false));
  }
  for (let i = 0; i < unique.length; i++) {
    const first = unique[i].page;
    const last = (i + 1 < unique.length) ? unique[i + 1].page - 1 : pageCount - 1;
    chapters.push(copyWith({
      id: nextId++,
      title: '',
      firstPage: first,
      lastPage: last,
      manual: false
    }, unique[i].title, first, last, false));
  }
  return chapters;
}

export function chapterAt(chapters: Array<Chapter>, page: number): number {
  for (let i = 0; i < chapters.length; i++) {
    if (page >= chapters[i].firstPage && page <= chapters[i].lastPage) {
      return i;
    }
  }
  return -1;
}

function nextIdOf(chapters: Array<Chapter>): number {
  let max = -1;
  for (const c of chapters) {
    if (c.id > max) {
      max = c.id;
    }
  }
  return max + 1;
}

// 分章夹子：把一章从 atPage 夹成两半；atPage 越界时夹取到合法边界
export function split(chapters: Array<Chapter>, index: number, atPage: number): Array<Chapter> {
  if (index < 0 || index >= chapters.length) {
    return chapters;
  }
  const target = chapters[index];
  const clamped = Math.max(target.firstPage + 1, Math.min(target.lastPage, atPage));
  if (clamped > target.lastPage) {
    return chapters;
  }
  const left = copyWith(target, target.title, target.firstPage, clamped - 1, target.manual);
  const right = copyWith(target, '未命名', clamped, target.lastPage, true);
  right.id = nextIdOf(chapters);
  const out: Array<Chapter> = [];
  for (let i = 0; i < chapters.length; i++) {
    if (i === index) {
      out.push(left);
      out.push(right);
    } else {
      out.push(chapters[i]);
    }
  }
  return out;
}

// 合并 index 与 index+1，保留前者标题；已是最后一章则原样返回
export function mergeNext(chapters: Array<Chapter>, index: number): Array<Chapter> {
  if (index < 0 || index + 1 >= chapters.length) {
    return chapters;
  }
  const merged = copyWith(chapters[index], chapters[index].title,
    chapters[index].firstPage, chapters[index + 1].lastPage, true);
  const out: Array<Chapter> = [];
  for (let i = 0; i < chapters.length; i++) {
    if (i === index) {
      out.push(merged);
    } else if (i === index + 1) {
      continue;
    } else {
      out.push(chapters[i]);
    }
  }
  return out;
}

export function rename(chapters: Array<Chapter>, index: number, title: string): Array<Chapter> {
  if (index < 0 || index >= chapters.length) {
    return chapters;
  }
  const out: Array<Chapter> = [];
  for (let i = 0; i < chapters.length; i++) {
    out.push(i === index ? copyWith(chapters[i], title, chapters[i].firstPage,
      chapters[i].lastPage, chapters[i].manual) : chapters[i]);
  }
  return out;
}

// 拖动章缝：rightIndex 章的新起点；越界夹取到 (左章.first, 右章.last] 内
export function moveBoundary(chapters: Array<Chapter>, rightIndex: number,
  newFirstPage: number): Array<Chapter> {
  if (rightIndex <= 0 || rightIndex >= chapters.length) {
    return chapters;
  }
  const left = chapters[rightIndex - 1];
  const right = chapters[rightIndex];
  const clamped = Math.max(left.firstPage + 1, Math.min(right.lastPage, newFirstPage));
  const out: Array<Chapter> = [];
  for (let i = 0; i < chapters.length; i++) {
    if (i === rightIndex - 1) {
      out.push(copyWith(left, left.title, left.firstPage, clamped - 1, true));
    } else if (i === rightIndex) {
      out.push(copyWith(right, right.title, clamped, right.lastPage, right.manual));
    } else {
      out.push(chapters[i]);
    }
  }
  return out;
}
