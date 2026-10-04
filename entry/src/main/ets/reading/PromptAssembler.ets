// 上下文组装（问答管线设计·前缀稳定性）：stable = L0规则+L1全书+L2本章，
// 会话内不变以命中厂商上下文缓存；dynamic = L3圈选+L4检索块+L5笔记+L6问句。

export interface SourceBlock {
  id: number;
  sourceLine: string;
  text: string;
}

export interface PromptParts {
  bookSummary: string;
  chapterContext: string;
  circledContent: string;
  blocks: Array<SourceBlock>;
  notes: string;
  question: string;
}

export interface AssembledPrompt {
  stable: string;
  dynamic: string;
}

const RULES = '你是亦书的伴读AI。回答规则：\n' +
  '1. 只依据给出的上下文作答，上下文没有就直说；\n' +
  '2. 关键结论后用[^编号]标注来源；\n' +
  '3. 只能引用上下文中给出的编号，不得编造；\n' +
  '4. 用已学内容解释新概念，不引入后面的章节。';

// L4 检索块的字符预算（约2.4k token），给圈选/笔记/问句留空间
const BLOCK_BUDGET_CHARS = 3600;

export function assemblePrompt(parts: PromptParts): AssembledPrompt {
  let stable = RULES;
  if (parts.bookSummary !== '') {
    stable += '\n【本书】' + parts.bookSummary;
  }
  if (parts.chapterContext !== '') {
    stable += '\n【本章】' + parts.chapterContext;
  }
  let dynamic = '';
  if (parts.circledContent !== '') {
    dynamic += '【圈选内容】' + parts.circledContent + '\n';
  }
  if (parts.blocks.length > 0) {
    dynamic += '【书中相关位置】\n';
    let used = 0;
    for (const b of parts.blocks) {
      if (used + b.text.length > BLOCK_BUDGET_CHARS) {
        break;
      }
      dynamic += `【${b.id}】${b.sourceLine}\n${b.text}\n`;
      used += b.text.length;
    }
  }
  if (parts.notes !== '') {
    dynamic += '【相关笔记】' + parts.notes + '\n';
  }
  dynamic += '【问题】' + parts.question;
  const p: AssembledPrompt = { stable: stable, dynamic: dynamic };
  return p;
}
