import { describe, it, expect } from '@ohos/hypium';
import { indexButtonLabel, coverCellScale, coverCellShift, shelfColumns,
  coverCellWidthPct, bookDetailStats, staleBadgeLabel, detailPrimaryLabel } from '../main/ets/view/PresentationMath';

// 视图层纯呈现计算的行为网。
// 这些分支原本埋在 1949 行 / 960 行的 ArkUI 组件里，零测试覆盖。

export default function presentationMathTest() {
  describe('presentationMath', () => {

    it('index button text follows a fixed priority order', 0, () => {
      // 版式分析优先于一切
      expect(indexButtonLabel('分析 3/40', '建索引…', true, 60, 100)).assertEqual('分析 3/40');
      // 其次建索引进度
      expect(indexButtonLabel('', '建索引…', true, 60, 100)).assertEqual('建索引…');
      // 已索引但未覆盖全书 → 显示进度
      expect(indexButtonLabel('', '', true, 60, 100)).assertEqual('索引 60/100');
      // 已覆盖全书
      expect(indexButtonLabel('', '', true, 100, 100)).assertEqual('已索引');
      // 尚未索引：哪怕 cap 小于总页数也只显示「索引」
      expect(indexButtonLabel('', '', false, 60, 100)).assertEqual('索引');
    });

    it('cover cell dips into its shadow on press and lifts on hover', 0, () => {
      expect(coverCellScale('s1', 's1', '')).assertEqual(0.97);
      expect(coverCellScale('s1', '', 's1')).assertEqual(1.03);
      expect(coverCellScale('s1', '', '')).assertEqual(1.0);
      // 按压优先于悬停
      expect(coverCellScale('s1', 's1', 's1')).assertEqual(0.97);
      // 别的单元不受影响
      expect(coverCellScale('s2', 's1', 's1')).assertEqual(1.0);

      expect(coverCellShift('s1', 's1')).assertEqual(4);
      expect(coverCellShift('s1', '')).assertEqual(0);
      expect(coverCellShift('s2', 's1')).assertEqual(0);
    });

    it('fewer books means fewer and larger columns', 0, () => {
      expect(shelfColumns(0)).assertEqual(3);
      expect(shelfColumns(3)).assertEqual(3);
      expect(shelfColumns(4)).assertEqual(4);
      expect(shelfColumns(8)).assertEqual(4);
      expect(shelfColumns(9)).assertEqual(5);
      expect(shelfColumns(500)).assertEqual(5);
    });

    it('cell width follows the column count with a safe fallback', 0, () => {
      expect(coverCellWidthPct(3)).assertEqual('29%');
      expect(coverCellWidthPct(4)).assertEqual('21.5%');
      expect(coverCellWidthPct(5)).assertEqual('17%');
      // 未预期的列数走兜底，不返回空串
      expect(coverCellWidthPct(2)).assertEqual('17%');
    });

    it('detail stats show the read page and draft only when they exist', 0, () => {
      expect(bookDetailStats(0, -1, false)).assertEqual('问答 0');
      // highWater 是 0 基下标，显示时 +1
      expect(bookDetailStats(3, 9, false)).assertEqual('问答 3 · 已读 P10');
      expect(bookDetailStats(3, 0, false)).assertEqual('问答 3 · 已读 P1');
      expect(bookDetailStats(3, -1, true)).assertEqual('问答 3 · 有草稿');
      expect(bookDetailStats(3, 9, true)).assertEqual('问答 3 · 已读 P10 · 有草稿');
    });

    it('marks a stale entry and re-routes its primary action', 0, () => {
      expect(staleBadgeLabel(true)).assertEqual('文件已丢失');
      expect(staleBadgeLabel(false)).assertEqual('');
      // 文件已不在设备里时，「开始阅读」是骗人的；换成真正的出路
      expect(detailPrimaryLabel(true, 9)).assertEqual('从书架移除');
      expect(detailPrimaryLabel(true, -1)).assertEqual('从书架移除');
      // 正常书维持原样
      expect(detailPrimaryLabel(false, 9)).assertEqual('继续阅读 P10');
      expect(detailPrimaryLabel(false, 0)).assertEqual('继续阅读 P1');
      expect(detailPrimaryLabel(false, -1)).assertEqual('开始阅读');
    });
  });
}
