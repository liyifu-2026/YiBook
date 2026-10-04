// 建书编排的端口（契约）：BookIndexer 只依赖这些抽象，不依赖任何具体实现。
//
// 存在的两个理由：
//   1) 解耦——book 域不再 import ai 域的具体客户端，消除 book ↔ ai 域级交叉引用；
//   2) 可测——已实测：本地单测运行时无法执行 @kit 文件 IO 与网络
//      （写文件返回 false），端口让单测注入纯内存替身。
//
// 实现方：TextEmbedder ← ai/EmbeddingClient，PageVision ← ai/VisionClient，
//        VectorCache ← book/IndexCache。
// 本文件必须保持纯逻辑，禁止 import @ohos / @kit。

export interface CacheData {
  hashes: Array<string>;
  dims: number;
  data: Float32Array;
}

// 文本向量化（可缺席：BYOK 未配 embeddings 时 available() 为 false，检索退化为词法单路）
export interface TextEmbedder {
  available(): boolean;
  embed(texts: Array<string>): Promise<Array<Array<number>>>;
}

// 图像文字识别（二期 OCR 管线：只转录缺文字层的页）
export interface PageVision {
  available(): boolean;
  extractText(imageBase64: string, mime: string): Promise<string>;
}

// 向量缓存（跨会话零重复计费）；设备侧由 book/IndexCache 以 @kit 文件 IO 实现
export interface VectorCache {
  load(): CacheData | null;
  save(hashes: Array<string>, dims: number, data: Float32Array): void;
}

// 页面文本来源（T0 文字层直提）；实现方：pdf/PdfPageSource
export interface PageTextSource {
  pageText(index: number): string;
}

// 整页图像来源（T1/T3 走视觉模型 OCR）。实现方：pdf/PdfPageSource。
// 刻意只暴露「整页 JPEG」这一语义：OCR 不需要裁框，
// 原先调用处传 null bbox + 哑栅格，等价于整页出图。
export interface PageImageSource extends PageTextSource {
  pageJpegBase64(index: number): Promise<string>;
}
