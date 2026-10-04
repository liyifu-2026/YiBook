// PDF 打开失败的成因判定与文案（纯逻辑）。
//
// 为什么需要它：pdfService 的 ParseResult 本来就把失败分成四类，但
// PdfPageSource.open() 只回 boolean、返回码只写进日志。结果「文件已不在设备里」
// 与「格式不受支持」对用户说同一句话（「文件可能已损坏或格式不受支持」），
// 还都配一个注定无效的「重试」——用户既不知道发生了什么，也没有出路。
//
// 调研报告决策 #38 定了失败态 UI 的存在（黑猫 + 一句话 + 行动点），
// 本模块只负责决定那「一句话」该说什么、行动点是否值得给。
//
// 本文件必须保持纯逻辑，禁止 import @ohos / @kit 与 ArkUI。

// pdfService.ParseResult 的字面量（SDK d.ts：PARSE_SUCCESS / ERROR_FILE /
// ERROR_FORMAT / ERROR_PASSWORD / ERROR_HANDLER）。沿用数字比较，不用枚举常量，
// 防运行时常量解析差异（与 PdfPageSource 原有注释一致）。
export const PARSE_SUCCESS = 0;
export const PARSE_ERROR_FILE = 1;
export const PARSE_ERROR_FORMAT = 2;
export const PARSE_ERROR_PASSWORD = 3;
export const PARSE_ERROR_HANDLER = 4;
// 本地哨兵：loadDocument 直接抛异常，SDK 没给码
export const PARSE_THREW = -1;

export enum OpenProblem {
  None = 0,
  // 文件不在设备里，或存在但读不了（PARSE_ERROR_FILE）
  FileMissingOrUnreadable = 1,
  UnsupportedFormat = 2,
  PasswordProtected = 3,
  Unknown = 4
}

export interface OpenDiagnosis {
  problem: OpenProblem;
  title: string;
  hint: string;
  canRetry: boolean; // 「重试」只有在成因不是「文件没了/要密码」时才有意义
}

// fileExists 由调用方传入（纯逻辑不做 IO）。
// 判定优先级：文件不存在 > 解析码 > 兜底。
export function diagnoseOpen(parseCode: number, fileExists: boolean): OpenDiagnosis {
  if (parseCode === PARSE_SUCCESS) {
    const ok: OpenDiagnosis = { problem: OpenProblem.None, title: '', hint: '', canRetry: false };
    return ok;
  }
  if (!fileExists) {
    const gone: OpenDiagnosis = {
      problem: OpenProblem.FileMissingOrUnreadable,
      title: '这本书的文件已丢失',
      hint: '书还在书架上，但文件已经不在设备里了。回书房移除它，再重新导入一次。',
      canRetry: false
    };
    return gone;
  }
  if (parseCode === PARSE_ERROR_FILE) {
    const unreadable: OpenDiagnosis = {
      problem: OpenProblem.FileMissingOrUnreadable,
      title: '这本书的文件读不了',
      hint: '文件还在，但打不开。回书房移除它，再重新导入一次。',
      canRetry: false
    };
    return unreadable;
  }
  if (parseCode === PARSE_ERROR_FORMAT) {
    const fmt: OpenDiagnosis = {
      problem: OpenProblem.UnsupportedFormat,
      title: '这本书暂时打不开',
      hint: '这个 PDF 的格式无法解析。',
      canRetry: true
    };
    return fmt;
  }
  if (parseCode === PARSE_ERROR_PASSWORD) {
    const pwd: OpenDiagnosis = {
      problem: OpenProblem.PasswordProtected,
      title: '这本书有密码',
      hint: '暂不支持打开加密的 PDF。',
      canRetry: false
    };
    return pwd;
  }
  // PARSE_ERROR_HANDLER / PARSE_THREW / 未知码：保持决策 #38 的通用失败态文案
  const unknown: OpenDiagnosis = {
    problem: OpenProblem.Unknown,
    title: '这本书暂时打不开',
    hint: '文件可能已损坏或格式不受支持',
    canRetry: true
  };
  return unknown;
}
