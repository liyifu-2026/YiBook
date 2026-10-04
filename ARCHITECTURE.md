# YiBook 架构

鸿蒙平板上的「连续阅读」学习空间：PDF 长卷阅读 + 手写圈选提问 + 本地检索 + 云端 BYOK 作答。

需求唯一来源是 `F:\Markdown\亦书\` 下的产品文档；本文件只描述**代码怎么组织**，产品行为与决策记录以那些文档和 `AGENTS.md` 为准。

---

## 1. 源码分层

```
entry/src/main/ets/
├── pages/               @Entry 页面入口（main_pages.json 引用，勿移动）
├── entryability/        UIAbility 生命周期
├── entrybackupability/  备份扩展
│
├── view/                ← ArkUI 界面层（第 3 层）
│   LibraryView / ReaderView / StudyRoomView
│
├── ink/                 ┐
├── ai/                  │
├── book/                ├ 业务域（第 2 层）
├── search/              │
├── pdf/                 │
├── review/              ┘
│
└── core/                ← 通用基础设施（第 1 层）
    JsonFile / Sse / Theme
```

**共 8 个业务域 + 3 个固定入口目录，42 个模块。**

`pages/Index.ets` 必须留在 `pages/`：`entry/src/main/resources/base/profile/main_pages.json` 按 `"pages/Index"` 引用它，移动会导致应用起不来。

---

## 2. 各域职责

| 域 | 职责 | 模块 |
|---|---|---|
| **core** | 与业务无关的基础设施：文件读写、SSE 流解析、配色 | `JsonFile` `Sse` `Theme` |
| **pdf** | PDF 取页与长卷几何：渲染窗、连续布局、裁白边、屏幕↔页面坐标变换 | `PdfPageSource` `RenderWindow` `ContinuousLayout` `ReaderGeometry` `CropMath` `CropPipeline` `ScanPipeline` |
| **book** | 书架、章节模型、索引构建与缓存、已读水位 | `BookshelfModel` `ChapterModel` `BookIndexer` `IndexerMath` `IndexCache` `OcrTexts` `ReadingProgress` |
| **search** | 本地双路检索与融合：分块、词法、向量、RRF+MMR、路由 | `Chunker` `LexicalIndex` `VectorIndex` `RankFusion` `QueryRouter` `SearchOrchestrator` `KnowledgeBase` |
| **ai** | BYOK 云端链路：LLM/向量/视觉客户端、提示词装配、回答解析、问答记录 | `LlmClient` `EmbeddingClient` `VisionClient` `PromptAssembler` `ContextSummary` `AnswerParser` `Qa` |
| **ink** | 手写与圈选：笔画存储、序列化、手势判定、提问气泡 | `InkStore` `InkPersistence` `GestureMath` `Gestures` `BubbleModel` `PageInkCanvas` |
| **review** | 间隔重复复习队列 | `Review` `ReviewQueue` |
| **view** | ArkUI 界面层，唯一顶层 | `LibraryView` `ReaderView` `StudyRoomView` |

---

## 3. 依赖方向（实测，非设计意图）

以源码中实际的 `import` 统计（数字为引用处数）：

```
view ──> ai(9) book(8) core(5) ink(6) pdf(9) review(2) search(5)
book ──> ai(2) pdf(2) search(4)
ai   ──> book(2) core(1)
ink  ──> pdf(4)
pdf  ──> book(2)
search ─> ai(1)
core ──> （无出边）
review ─> （无出边）
```

- **`view` 是唯一的严格顶层**：它对全部 7 个业务域都有出边，且没有任何域依赖 `view`。
- **`core` 与 `review` 是叶子**：不依赖任何其他域。
- 全图 **15 条跨域边，无模块级循环依赖**（已用 DFS 着色验证）。

### 已知交叉：`ai ↔ book` 与 `book ↔ pdf`

域标签层面存在两处**互相引用**，但都由不同模块承担，因此**不是真正的循环依赖**：

- `book/BookIndexer` → `ai/EmbeddingClient`、`ai/VisionClient`（索引要调向量/视觉）
- `ai/ContextSummary` → `book/ChapterModel`（摘要要读章节结构）
- `book/BookIndexer` → `pdf/PdfPageSource`、`pdf/CropPipeline`（索引要取页与降采样）
- `pdf/PdfPageSource`、`pdf/ScanPipeline` → `book/ChapterModel`（要 `OutlineMarker` 类型）

这是当前最大的结构债：`ChapterModel` 被 `pdf` 当作纯数据类型依赖，而 `BookIndexer` 把「编排」和「领域」混在一起。若将来要严格分层，建议把 `BookIndexer` 提到独立的编排域（如 `pipeline/`），并把 `OutlineMarker` 这类纯数据类型下沉到共享模型域。**当前不阻塞开发，未做处理。**

---

## 4. 分层铁律（可机检）

`AGENTS.md` 原则 2：**纯逻辑与 ArkUI 严格分离**——`entry/src/main/ets/<域>/` 下的算法模块禁止 `import @ohos.*` / `@kit.*`，保证本地单测可跑。

实测合规情况：

| 域 | 纯逻辑 | 含系统 API(`@kit`) | 含 ArkUI | 小计 |
|---|---:|---:|---:|---:|
| core | 2 | 1 | 0 | 3 |
| pdf | 6 | 1 | 0 | 7 |
| book | 6 | 1 | 0 | 7 |
| search | **7** | 0 | 0 | 7 |
| ai | 4 | 3 | 0 | 7 |
| ink | 5 | 0 | 1 | 6 |
| review | **2** | 0 | 0 | 2 |
| view | 0 | 0 | 3 | 3 |
| **合计** | **32** | **6** | **4** | **42** |

- `search/` 与 `review/` 是 **100% 纯逻辑**，任何改动都必须有单测覆盖。
- 6 个含系统 API 的模块：`core/JsonFile`、`pdf/PdfPageSource`、`book/IndexCache`、`ai/LlmClient`、`ai/EmbeddingClient`、`ai/VisionClient`。
- 4 个 ArkUI 模块：`ink/PageInkCanvas`、`view/LibraryView`、`view/ReaderView`、`view/StudyRoomView`。

新增算法模块时，**纯逻辑放对应业务域并配单测**；一旦需要 `@kit.*`，说明它在做 IO，应放进该域的客户端/适配模块，而不是让算法模块去 import。

---

## 5. 三条主数据流

**开书（先渲染后分析）**
`view/LibraryView` → `pdf/PdfPageSource` 探测第 0 页定纵横比 → 立即出首帧 → 后台分批跑 `pdf/CropPipeline` 版式分析 → 进度显示在索引按钮 → 完成后 `view/ReaderView` 重排应用裁剪。

**提问作答**
`ink/PageInkCanvas`（笔迹圈选）→ `ink/GestureMath` 判定手势 → `search/QueryRouter` 选路 → `search/SearchOrchestrator`（`LexicalIndex` + `VectorIndex` → `RankFusion` RRF → MMR top-6）→ `ai/PromptAssembler` 装配 → `ai/LlmClient` 流式作答 → `ai/AnswerParser` 校验引用 → `ai/Qa` 落库 → `ink/BubbleModel` 气泡。

**建索引**
`book/BookIndexer` → `pdf/PdfPageSource` 取页文本 → `book/OcrTexts`（扫描版走 OCR）→ `search/Chunker` 分块 → `book/IndexerMath` 规划缺口 → `ai/EmbeddingClient` 向量化 → `book/IndexCache` 缓存 → 写入 `search/LexicalIndex` + `search/VectorIndex`。

---

## 6. 关键不变量

以下为已定决策（详见 `AGENTS.md` 与调研报告决策表），改代码前必读：

1. **手指永远滚动、只有触控笔才书写**——`PageInkCanvas` 用 `touches[i].sourceTool === SourceTool.Pen` 过滤。无可妥协。
2. **长卷画布必须分块**（`CHUNK_MAX_VP = 1500`）：单 Stack 高超 GPU 纹理上限（约 4096–16384px）会**静默整块不渲染**，日志无错。
3. **`PdfPageSource.getPagePixelMap` 必须立即拷贝为独立 PixelMap**（`readPixelsToBuffer` → `createPixelMap`，顺带 alpha 压平成白底）；严禁 `writeBufferToPixels` 回写，会损坏显示通道。
4. **锚点基准**：PDF 原始页坐标 bbox + 文本层字符偏移双保险；裁白边只是视口变换。
5. **已读判定**：高水位线（到达过的最大页码），设置可手调。
6. **开书先渲染后分析**：只探测第 0 页定纵横比立即出首帧；整书版式分析转后台分批让出 UI 线程。

---

## 7. 构建与验证

```bash
export DEVECO_SDK_HOME="F:\deveco\DevEco Studio\sdk"

# 版本
node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" -v

# 本地单测（结果唯一凭据：entry/.test/default/intermediates/test/coverage_data/test_result.txt）
node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default test

# 无设备编译验证（改 ArkUI / kit 相关代码后必跑）
node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleHap
```

当前基线：**33 个测试文件 / 106 用例全通过**；`assembleHap` 通过。

> `build-profile.json5` 的 `signingConfigs` 已挖空（原含签名口令与设备证书路径）。
> 本地原值备份在 `.signing-config.backup.json5`（已 gitignore，不入库）。
> 真机部署前需在 DevEco Studio 中勾选 **File > Project Structure > Signing Configs > Automatically generate signature**，它会自动回填该字段——这是编译期 warning `Will skip sign 'hos_hap'` 的原因，不影响 `assembleHap`。
> 前置：真机 profile 绑定「包名 + 设备 UDID」，OpenHarmony 自签材料不适用于华为商用平板。

---

## 8. 新增代码放哪里

| 你要做的事 | 放这里 |
|---|---|
| 纯算法 / 纯数据变换 | 对应业务域，配 `entry/src/test/<Name>.test.ets` |
| 调用鸿蒙系统能力（IO/网络/图形） | 该域的客户端模块，**不要**放进算法模块 |
| 新的 ArkUI 界面 | `view/`，并在 `pages/Index.ets` 挂接 |
| 与 PDF 页坐标/几何相关 | `pdf/` |
| 检索策略、排序、召回 | `search/` |
| 提示词、模型调用、回答后处理 | `ai/` |
| 笔迹、手势、气泡 | `ink/` |
| 跨域复用的无业务工具 | `core/` |

**测试夹具**：逻辑测试放 `entry/src/test/fixtures/`，应用运行时资源放 `entry/src/main/resources/rawfile/`。

---

## 9. 已知技术债

1. **`ai ↔ book`、`book ↔ pdf` 域级交叉引用**（见 §3），当前无环、不阻塞，但阻碍严格分层。
2. **两个巨型视图**：`view/ReaderView.ets` 1823 行、`view/LibraryView.ets` 908 行，职责过载，是后续拆分重点。
3. **双 agent 协作边界**：UI 视觉由独立 agent 负责。本次分域重构已移动全部界面文件路径（`reading/` → `view/`、`ink/` 等），该 agent 手上的旧路径全部失效，需同步告知。
4. **`LibraryView_new.ets`** 是仓库根目录下的界面草稿（未被编译，import 仍指向旧路径 `./BookshelfModel`），需由 UI 侧决定是并入 `view/LibraryView.ets` 还是删除。
5. **`entry/src/main/resources/rawfile/sample_textbook.pdf` 实为扫描版**（无文字层、书签为逐页垃圾），文本锚定与章节提取的真验证仍需一份**带文字层 + 真书签**的原生 PDF。
