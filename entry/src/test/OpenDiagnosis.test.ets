import { describe, it, expect } from '@ohos/hypium';
import { diagnoseOpen, OpenProblem, PARSE_SUCCESS, PARSE_ERROR_FILE,
  PARSE_ERROR_FORMAT, PARSE_ERROR_PASSWORD, PARSE_ERROR_HANDLER,
  PARSE_THREW } from '../main/ets/pdf/OpenDiagnosis';

// 打开失败的成因判定。
// 这件事原本没有测试、也没有区分：/open() 只回 boolean，返回码只进日志，
// 于是「文件已不在设备里」和「格式不受支持」对用户说同一句话，还都配一个注定无效的重试。
// PDF 的打开行为只能上真机验（@kit.PDFKit），但「码 + 文件在不在」到「说哪句话」的映射
// 是纯逻辑，必须在本地锁住。

export default function openDiagnosisTest() {
  describe('openDiagnosis', () => {

    it('has nothing to explain when the file opened', 0, () => {
      const d = diagnoseOpen(PARSE_SUCCESS, true);
      expect(d.problem).assertEqual(OpenProblem.None);
      expect(d.canRetry).assertFalse();
    });

    it('says the file is gone — not "corrupt" — and offers no futile retry', 0, () => {
      const d = diagnoseOpen(PARSE_ERROR_FILE, false);
      expect(d.problem).assertEqual(OpenProblem.FileMissingOrUnreadable);
      expect(d.title).assertEqual('这本书的文件已丢失');
      expect(d.canRetry).assertFalse();
      // 必须告诉用户出路（回书房移除），否则就是死路
      expect(d.hint.indexOf('移除') >= 0).assertTrue();
    });

    it('trusts a missing file over whatever the parser reported', 0, () => {
      // 文件都不在了，报什么码都不重要：按「丢失」说，不能按「格式」说
      const fmt = diagnoseOpen(PARSE_ERROR_FORMAT, false);
      expect(fmt.problem).assertEqual(OpenProblem.FileMissingOrUnreadable);
      expect(fmt.canRetry).assertFalse();
      const pwd = diagnoseOpen(PARSE_ERROR_PASSWORD, false);
      expect(pwd.problem).assertEqual(OpenProblem.FileMissingOrUnreadable);
    });

    it('treats a file-level error on an existing file as unreadable', 0, () => {
      const d = diagnoseOpen(PARSE_ERROR_FILE, true);
      expect(d.problem).assertEqual(OpenProblem.FileMissingOrUnreadable);
      expect(d.title).assertEqual('这本书的文件读不了');
      expect(d.canRetry).assertFalse();
    });

    it('keeps the retry only where it can actually help', 0, () => {
      const fmt = diagnoseOpen(PARSE_ERROR_FORMAT, true);
      expect(fmt.problem).assertEqual(OpenProblem.UnsupportedFormat);
      expect(fmt.canRetry).assertTrue();

      const pwd = diagnoseOpen(PARSE_ERROR_PASSWORD, true);
      expect(pwd.problem).assertEqual(OpenProblem.PasswordProtected);
      expect(pwd.canRetry).assertFalse();
      expect(pwd.title).assertEqual('这本书有密码');
    });

    it('falls back to the decided generic failure copy (决策 #38)', 0, () => {
      const handler = diagnoseOpen(PARSE_ERROR_HANDLER, true);
      expect(handler.problem).assertEqual(OpenProblem.Unknown);
      expect(handler.title).assertEqual('这本书暂时打不开');
      expect(handler.hint).assertEqual('文件可能已损坏或格式不受支持');
      expect(handler.canRetry).assertTrue();

      // 抛异常但文件还在：成因不明，仍按通用失败态、仍给重试
      const threw = diagnoseOpen(PARSE_THREW, true);
      expect(threw.problem).assertEqual(OpenProblem.Unknown);
      expect(threw.canRetry).assertTrue();
    });
  });
}
