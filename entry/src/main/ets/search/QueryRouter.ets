// 查询路由（问答管线设计·机制1）：纯规则决定检索范围，0 token。
// 优先级：位置检索 > 追问 > 圈选速查 > 通用。

export enum QueryRoute {
  CircledLookup = 0,
  FollowUp = 1,
  LocateInBook = 2,
  General = 3
}

const LOCATE_WORDS: Array<string> = ['哪里', '哪些', '哪儿', '何处', '哪几'];
const DEIXIS_WORDS: Array<string> = ['这个', '那个', '它', '为什么', '接着', '继续', '呢'];

function containsAny(text: string, words: Array<string>): boolean {
  for (const w of words) {
    if (text.indexOf(w) >= 0) {
      return true;
    }
  }
  return false;
}

export function routeQuery(hasCircled: boolean, question: string, hasPreviousTurn: boolean): QueryRoute {
  const q = question.trim();
  if (containsAny(q, LOCATE_WORDS)) {
    return QueryRoute.LocateInBook;
  }
  if (hasPreviousTurn && containsAny(q, DEIXIS_WORDS)) {
    return QueryRoute.FollowUp;
  }
  if (hasCircled && q.length <= 15) {
    return QueryRoute.CircledLookup;
  }
  return QueryRoute.General;
}
