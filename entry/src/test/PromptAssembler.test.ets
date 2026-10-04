import { describe, it, expect } from '@ohos/hypium';
import { assemblePrompt, PromptParts, SourceBlock } from '../main/ets/reading/PromptAssembler';

function block(id: number, text: string): SourceBlock {
  const b: SourceBlock = { id: id, sourceLine: `P${id}`, text: text };
  return b;
}

export default function promptAssemblerTest() {
  describe('promptAssembler', () => {
    it('stable prefix keeps rules, book and chapter; dynamic carries L3-L6', 0, () => {
      const parts: PromptParts = {
        bookSummary: '本书讲C++竞赛入门',
        chapterContext: '本章讲顺序结构',
        circledContent: 'cout 语句',
        blocks: [block(1, '块内容')],
        notes: '我的笔记',
        question: '这是什么意思'
      };
      const p = assemblePrompt(parts);
      expect(p.stable.indexOf('回答规则') >= 0).assertTrue();
      expect(p.stable.indexOf('本书讲C++竞赛入门') >= 0).assertTrue();
      expect(p.stable.indexOf('本章讲顺序结构') >= 0).assertTrue();
      expect(p.dynamic.indexOf('cout 语句') >= 0).assertTrue();
      expect(p.dynamic.indexOf('【1】') >= 0).assertTrue();
      expect(p.dynamic.indexOf('我的笔记') >= 0).assertTrue();
      expect(p.dynamic.indexOf('这是什么意思') > p.dynamic.indexOf('我的笔记')).assertTrue();
    });

    it('empty parts leave no empty section headings', 0, () => {
      const parts: PromptParts = {
        bookSummary: '',
        chapterContext: '',
        circledContent: '',
        blocks: [],
        notes: '',
        question: '作者是谁'
      };
      const p = assemblePrompt(parts);
      expect(p.stable.indexOf('【本书】') < 0).assertTrue();
      expect(p.dynamic.indexOf('【圈选内容】') < 0).assertTrue();
      expect(p.dynamic.indexOf('【相关笔记】') < 0).assertTrue();
      expect(p.dynamic.indexOf('作者是谁') >= 0).assertTrue();
    });

    it('blocks beyond char budget are dropped, earlier ones kept', 0, () => {
      const blocks: Array<SourceBlock> = [];
      for (let i = 1; i <= 10; i++) {
        blocks.push(block(i, '内容'.repeat(300)));
      }
      const parts: PromptParts = {
        bookSummary: '',
        chapterContext: '',
        circledContent: '',
        blocks: blocks,
        notes: '',
        question: '总结'
      };
      const p = assemblePrompt(parts);
      expect(p.dynamic.indexOf('【1】') >= 0).assertTrue();
      expect(p.dynamic.indexOf('【10】') < 0).assertTrue();
    });
  });
}
