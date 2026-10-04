import { describe, it, expect } from '@ohos/hypium';
import { markersFromTocText } from '../main/ets/reading/ScanPipeline';

export default function scanPipelineTest() {
  describe('scanPipeline', () => {
    it('parses chapter lines with dotted leaders, ignores sections', 0, () => {
      const toc = [
        '前言',
        '第1章　初识C++语言……………………2',
        '1.1　程序与计算机语言………………3',
        '第 3 章 分支结构 ······ 28',
        '第12章 动态规划初步',
        '第2章　顺序结构程序设计…14'
      ].join('\n');
      const markers = markersFromTocText(toc);
      expect(markers.length).assertEqual(3);
      expect(markers[0].title).assertEqual('第1章 初识C++语言');
      expect(markers[0].page).assertEqual(2);
      expect(markers[1].title).assertEqual('第2章 顺序结构程序设计');
      expect(markers[1].page).assertEqual(14);
      expect(markers[2].title).assertEqual('第3章 分支结构');
      expect(markers[2].page).assertEqual(28);
    });

    it('markers come out page-ascending regardless of text order', 0, () => {
      const toc = '第2章 顺序结构 14\n第1章 初识 2';
      const markers = markersFromTocText(toc);
      expect(markers.length).assertEqual(2);
      expect(markers[0].title).assertEqual('第1章 初识');
      expect(markers[0].page).assertEqual(2);
      expect(markers[1].title).assertEqual('第2章 顺序结构');
      expect(markers[1].page).assertEqual(14);
    });
  });
}
