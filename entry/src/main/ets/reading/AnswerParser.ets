// 回答解析与引用校验（防幻觉引用）：只保留指向给定块的编号，
// 越界编号从正文剔除；有效编号去重后按出现顺序返回。

export interface ParsedAnswer {
  text: string;
  refs: Array<number>;
}

export function parseAnswer(raw: string, validIds: Array<number>): ParsedAnswer {
  const refs: Array<number> = [];
  const seen = new Set<number>();
  const re = new RegExp('\\[\\^(\\d+)\\]', 'g');
  let text = raw;
  let m = re.exec(raw);
  while (m !== null) {
    const n = parseInt(m[1], 10);
    let valid = false;
    for (const v of validIds) {
      if (v === n) {
        valid = true;
        break;
      }
    }
    if (valid) {
      if (!seen.has(n)) {
        seen.add(n);
        refs.push(n);
      }
    } else {
      text = text.split(m[0]).join('');
    }
    m = re.exec(raw);
  }
  const out: ParsedAnswer = { text: text, refs: refs };
  return out;
}
