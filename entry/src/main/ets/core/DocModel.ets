// 跨域共享的文档纯数据类型。
//
// 为什么放在 core 而不是 book：pdf 域（从 PDF 书签抽取标记）与 ai 域（建书摘要）
// 都要用到这些类型，若定义留在 book 就会形成 pdf → book、ai → book 的域级交叉引用。
// 类型下沉到 core 后，pdf / ai 只依赖 core，交叉消失。
//
// 本文件必须保持纯逻辑，禁止 import @ohos / @kit。

// PDF 书签 / 目录项：页内的一个分章标记
export interface OutlineMarker {
  title: string;
  page: number;
}

// 章节：不变式为按 firstPage 升序且连续覆盖 [0, pageCount-1]
export interface Chapter {
  id: number;
  title: string;
  firstPage: number;
  lastPage: number;
  manual: boolean;
}
