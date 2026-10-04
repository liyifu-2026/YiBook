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
│   LibraryView / ReaderView / StudyRoomView + 纯呈现计算 PresentationMath
│
├── ink/                 ┐
├── ai/                  │
├── book/                ├ 业务域（第 2 层）
├── search/              │
├── pdf/                 │
├── review/              ┘
│
└── core/                ← 通用基础设施与共享契约（第 1 层）
    JsonFile / Sse / Theme / Ports / DocModel / Batching
```

**共 8 个业务域 + 3 个固定入口目录，48 个模块。**

`pages/Index.ets` 必须留在 `pages/`：`entry/src/main/resources/base/profile/main_pages.json` 按 `"pages/Index"` 引用它，移动会导致应用起不来。

---

## 2. 各域职责

| 域 | 职责 | 模块 |
|---|---|---|
| **core** | 与业务无关的基础设施 + 跨域共享契约：文件读写、SSE 流解析、配色、**端口接口**、**共享纯数据类型** | `JsonFile` `Sse` `Theme` `Ports` `DocModel` `Batching` |
| **pdf** | PDF 取页与长卷几何：渲染窗、连续布局、**自动裁白边**、屏幕↔页面坐标变换、**长卷分块与可见窗口** | `PdfPageSource` `RenderWindow` `ContinuousLayout` `ReaderGeometry` `AutoCrop` `CropMath` `CropPipeline` `ScanPipeline` `ChunkWindow` |
| **book** | 书架、章节模型、索引构建与缓存、已读水位 | `BookshelfModel` `ChapterModel` `BookIndexer` `IndexerMath` `IndexCache` `OcrTexts` `ReadingProgress` |
| **search** | 本地双路检索与融合：分块、词法、向量、RRF+MMR、路由 | `Chunker` `LexicalIndex` `VectorIndex` `RankFusion` `QueryRouter` `SearchOrchestrator` `KnowledgeBase` |
| **ai** | BYOK 云端链路：LLM/向量/视觉客户端、提示词装配、回答解析、问答记录 | `LlmClient` `EmbeddingClient` `VisionClient` `PromptAssembler` `ContextSummary` `AnswerParser` `Qa` |
| **ink** | 手写与圈选：笔画存储、序列化、手势判定、提问气泡 | `InkStore` `InkPersistence` `GestureMath` `Gestures` `BubbleModel` `PageInkCanvas` |
| **review** | 间隔重复复习队列 | `Review` `ReviewQueue` |
| **view** | ArkUI 界面层，唯一顶层；外加视图自己的**纯呈现计算**（按钮文案、封面形变、书架列数等） | `LibraryView` `ReaderView` `StudyRoomView` `PresentationMath` |

---

## 3. 依赖方向（实测，非设计意图）

以源码中实际的 `import` 统计（数字为引用处数）：

```
view ──> ai(9) book(8) core(6) ink(6) pdf(10) review(2) search(5)
book ──> core(3) search(4)
ai   ──> core(5)
ink  ──> pdf(4)
pdf  ──> core(3)
search ─> ai(1)
core ──> （无出边）
review ─> （无出边）
```

- **`view` 是唯一的严格顶层**：它对全部 7 个业务域都有出边，且没有任何域依赖 `view`。
- **`core` 与 `review` 是叶子**：不依赖任何其他域。
- 全图 **13 条跨域边，无模块级循环依赖**（已用 DFS 着色验证）。
- **无任何两域互相引用**——曾经的 `ai ↔ book`、`book ↔ pdf` 已消除（见下）。
- 仅存两处**单向**的类型级依赖，不构成环：`ink → pdf`（取 `BBox` / `DisplayTransform`）、`search → ai`（取 `SourceBlock`）。若想彻底让 `search` 也变成叶子，把 `SourceBlock` 一并下沉 `core/DocModel` 即可。

### 已消除的域级交叉（2026-10-04）

改造前有两处域级互引，现已彻底消除，手段是**端口契约 + 共享类型下沉**：

| 原交叉 | 成因 | 处置 |
|---|---|---|
| `book → ai` | `BookIndexer` 直接 `new EmbeddingClient` / `VisionClient` | 改为依赖 `core/Ports` 的 `TextEmbedder` / `PageVision`，具体实现由 `view/ReaderView` 注入 |
| `ai → book` | `ContextSummary` 要 `Chapter` 类型；`EmbeddingClient` 要 `batchTexts` | `Chapter`/`OutlineMarker` 下沉 `core/DocModel`；`batchTexts` 下沉 `core/Batching` |
| `book → pdf` | `BookIndexer` 直接用 `PdfPageSource` / `CropPipeline` | 改为依赖 `core/Ports` 的 `PageTextSource` / `PageImageSource`，由 `PdfPageSource` 实现 |
| `pdf → book` | `PdfPageSource`、`ScanPipeline` 要 `OutlineMarker` 类型 | 同上，类型下沉 `core/DocModel` |

### 端口契约与本地可测性

`core/Ports.ets` 是**纯契约**（不含 `@kit`），定义 5 个端口：

| 端口 | 语义 | 实现方 |
|---|---|---|
| `TextEmbedder` | 文本向量化（可缺席，缺席时检索退化为词法单路） | `ai/EmbeddingClient` |
| `PageVision` | 图像文字识别（OCR） | `ai/VisionClient` |
| `VectorCache` | 向量缓存读写（跨会话零重复计费） | `book/IndexCache` |
| `PageTextSource` | 页面文字层直提 | `pdf/PdfPageSource` |
| `PageImageSource` | 整页 JPEG（供 OCR） | `pdf/PdfPageSource` |

**为什么必须这么做（实测结论，非推测）**：本地单测跑在主机上，**无法执行 `@kit` 文件 IO 与网络**——`writeJsonFile` 会返回 `false`。因此只要编排层直接依赖 `IndexCache` 这类设备模块，它就永远不可能被本地单测覆盖。抽成端口后，`BookIndexer` 的行为已由 13 个用例以纯内存替身锁定（`entry/src/test/BookIndexer.test.ets`）。

> **测过才会踩的坑**：`fileExists` / `readJsonFile` 内部 `catch` 掉全部异常并返回 `false` / `null`。所以「读一个不存在的文件得到 `false`」**无法区分**「`@kit` 不可用」与「文件确实不存在」，是个假阳性探针。判断本地能否做 IO，必须用 `writeJsonFile(...) === true` 这类**只有真正成功才可能为真**的正控制。

---

## 4. 分层铁律（可机检）

`AGENTS.md` 原则 2：**纯逻辑与 ArkUI 严格分离**——`entry/src/main/ets/<域>/` 下的算法模块禁止 `import @ohos.*` / `@kit.*`，保证本地单测可跑。

实测合规情况：

| 域 | 纯逻辑 | 含系统 API(`@kit`) | 含 ArkUI | 小计 |
|---|---:|---:|---:|---:|
| core | 5 | 1 | 0 | 6 |
| pdf | 8 | 1 | 0 | 9 |
| book | 6 | 1 | 0 | 7 |
| search | **7** | 0 | 0 | 7 |
| ai | 4 | 3 | 0 | 7 |
| ink | 5 | 0 | 1 | 6 |
| review | **2** | 0 | 0 | 2 |
| view | 1 | 0 | 3 | 4 |
| **合计** | **38** | **6** | **4** | **48** |

- `search/` 与 `review/` 是 **100% 纯逻辑**，任何改动都必须有单测覆盖。
- `view/` 里的 `PresentationMath` 是**纯的**（列表见下），视图的呈现分支写在它里面而不是埋在组件里，才能被单测覆盖。
- 6 个含系统 API 的模块：`core/JsonFile`、`pdf/PdfPageSource`、`book/IndexCache`、`ai/LlmClient`、`ai/EmbeddingClient`、`ai/VisionClient`。
- 4 个 ArkUI 模块：`ink/PageInkCanvas`、`view/LibraryView`、`view/ReaderView`、`view/StudyRoomView`。

新增算法模块时，**纯逻辑放对应业务域并配单测**；一旦需要 `@kit.*`，说明它在做 IO，应放进该域的客户端/适配模块，而不是让算法模块去 import。

> **命名坑**：`view/PresentationMath` 里的函数名刻意与视图内的私有包装方法区分开（如 `indexButtonLabel` vs 私有方法 `indexButtonText`、`coverCellScale` vs `cellScale`）。若重名，`return cellWidthPct(...)` 这种「方法调用同名纯函数」的写法看起来像无限递归，极易误读——虽然 TS 里未限定名会走模块作用域、能正常编译。

---

## 5. 三条主数据流

**开书（先渲染后分析）**
`view/LibraryView` → `pdf/PdfPageSource` 探测第 0 页定纵横比 → 立即出首帧 → 后台分批跑 `pdf/CropPipeline` 版式分析 → 进度显示在索引按钮 → 完成后 `view/ReaderView` 重排应用裁剪。

**提问作答**
`ink/PageInkCanvas`（笔迹圈选）→ `ink/GestureMath` 判定手势 → `search/QueryRouter` 选路 → `search/SearchOrchestrator`（`LexicalIndex` + `VectorIndex` → `RankFusion` RRF → MMR top-6）→ `ai/PromptAssembler` 装配 → `ai/LlmClient` 流式作答 → `ai/AnswerParser` 校验引用 → `ai/Qa` 落库 → `ink/BubbleModel` 气泡。

**建索引**
`view/ReaderView` 注入端口实现（`PdfPageSource` → `PageImageSource`/`PageTextSource`，`EmbeddingClient` → `TextEmbedder`，`VisionClient` → `PageVision`，`IndexCache` → `VectorCache`）→ `book/BookIndexer` 取页文本 → `book/OcrTexts`（扫描版走 OCR）→ `search/Chunker` 分块 → `book/IndexerMath` 规划缺口 → `TextEmbedder.embed` 向量化 → `VectorCache.save` 落缓存 → 写入 `search/LexicalIndex` + `search/VectorIndex`。

---

## 6. 关键不变量

以下为已定决策（详见 `AGENTS.md` 与调研报告决策表），改代码前必读：

1. **手指永远滚动、只有触控笔才书写**——`PageInkCanvas` 用 `touches[i].sourceTool === SourceTool.Pen` 过滤。无可妥协。
2. **长卷画布必须分块**（`CHUNK_MAX_VP = 1500`）：单 Stack 高超 GPU 纹理上限（约 4096–16384px）会**静默整块不渲染**，日志无错。
3. **`PdfPageSource.getPagePixelMap` 必须立即拷贝为独立 PixelMap**（`readPixelsToBuffer` → `createPixelMap`，顺带 alpha 压平成白底）；严禁 `writeBufferToPixels` 回写，会损坏显示通道。
4. **锚点基准**：PDF 原始页坐标 bbox + 文本层字符偏移双保险；裁白边只是视口变换。
5. **已读判定**：高水位线（到达过的最大页码），设置可手调。
6. **开书先渲染后分析**：只探测第 0 页定纵横比立即出首帧；整书版式分析转后台分批让出 UI 线程。
7. **渲染窗口只能吃「绝对滚动位置」，绝不能吃 `onScroll` 的入参**：`Scroll.onScroll` 的两个入参是**相对上一帧的增量**，不是绝对滚动位置。把它当位置用的后果实测是「整本书只能看第一页、往下一片空白、页码恒为 P1」——`scrollY` 恒等于「最后一帧移动的那一点点」（真机实测 1.2~2.0 vp），渲染窗口于是永远算在 y≈0，只有第一块有内容、其余都是等高空占位。取值口径统一走 `pdf/RenderWindow` 的 `absoluteScrollOffset`（以 `scroller.currentOffset().yOffset` 为准，容器报不出位置时才退回增量累加），改动它有单测守着。
8. **纯阅读时零逐帧状态写入**：`refreshWindow` 只在渲染窗口真的变化时才重算 `visibleChunks`——它的键一变，整块的 `PageInkCanvas` 会被重挂，既打断正在写的笔画也是滑动卡顿的主要来源；`scrollY` 只在**有气泡需要跟随内容**时才逐帧写（没有气泡就没有任何理由每帧重渲染整棵树）。
9. **裁白边必须「四边各自稳健估计」，且以整本书为单位**（`pdf/AutoCrop`，带 13 个用例）：固定灰度阈值在扫描件上无解（实测偏暗页用旧阈值 180 会 100% 判成墨）；外接框对单点噪声零抵抗；**并集**对离群页零抵抗（少数出血页会把全书框拽到页边，边距永远裁不干净）。做法是：Otsu 自适应阈值 → 行/列投影 + 窗口**计数**抑制噪声 → 每条边取分位数（默认 `edgeQuantile=0.25`，只裁到 75% 的页都同意是空白的地方）→ 四分位距当一致性闸门（分布太散就**不裁**）→ `maxTrim` 夹住单边最多裁 25%。**四条边必须独立**：实测这本扫描件顶边近一半页有墨、而左右边距很一致，四边绑在一起判"版式是否一致"会互相否决、一页都裁不了。算出的框按书落盘（`crop_<key>.json`），第二次开书直接读回，版心从第一帧就是最终值、不再随分析进度跳变。

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

当前基线：**36 个测试文件 / 131 本地用例全通过**；`assembleHap` 通过；另有 3 个真机插桩用例（`entry/src/ohosTest/`，需设备）。

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

1. ~~`ai ↔ book`、`book ↔ pdf` 域级交叉引用~~ **已消除**（2026-10-04，见 §3）。遗留两处**单向**类型级依赖：`ink → pdf`、`search → ai`，不构成环。
2. **巨型视图：逻辑已拆、UI 结构已拆，但尚未拆成独立子组件**
   - **逻辑**（可测部分）：`pdf/ChunkWindow`（分块/可见窗口/LRU）、`view/PresentationMath`（按钮文案/封面形变/书架列数/统计行）、`ink/BubbleModel` 新增（气泡投影/点位指标），共 12 个新用例。
   - **UI 结构**：`view/ReaderView.build()` 由约 **765 行缩为 24 行薄壳**，11 个顶层段落移入具名 `@Builder`——`CanvasScroll` `LoadingLayer` `BubbleLayer` `BubblePins` `BubbleFoldBadge` `ClampLayer` `EdgeGestureStrip` `DraftBookmark` `ChapterPanel` `DraftPage` `BottomToolbar`。搬移是纯代码位移：用「代码行 **+44 / −0**」（净增仅为 11×`@Builder` + 11×签名 + 11×闭合 + 11×调用点）证明零丢失，并在 TGR-W10 上验证了渲染、滚动与错误态。
   - **仍未做**：把这些 `@Builder` 移入独立子 `@Component`（如 `view/reader/`）。这需要跨组件编排约 40 个 `@State`（`@Link`/`@ObjectLink`），属高风险改动，且界面文件归 UI agent 负责——动手前需与 UI 侧协调停手。
3. **双 agent 协作边界**：UI 视觉由独立 agent 负责。分域重构已移动全部界面文件路径（`reading/` → `view/`、`ink/` 等），该 agent 手上的旧路径全部失效，需同步告知。
4. ~~`LibraryView_new.ets` 草稿待定~~ **已删除**（2026-10-04）。它是截断的残缺草稿：82 个开括号对 71 个闭括号、**没有 `build()` 方法**、末尾停在表达式中间，根本无法编译；而现行的 `view/LibraryView.ets` 已远超它（953+ 行、5 个 `@Builder`、主题切换/封面轮换/缩略图/删除确认）。内容仍可从基线提交 `924d82a:LibraryView_new.ets` 取回。
5. **`entry/src/main/resources/rawfile/sample_textbook.pdf` 实为扫描版**（无文字层、书签为逐页垃圾），文本锚定与章节提取的真验证仍需一份**带文字层 + 真书签**的原生 PDF。
6. **`book/BookIndexer` 已补单测**（13 个用例，`build` 8 个 + `ensureOcr` 5 个），但它依赖的 `pdf/PdfPageSource` 面向真实 PDF 的解析行为**只能上真机验**——见 `entry/src/ohosTest/ets/test/NativePdf.test.ets`（3 个用例，已实测通过）。
7. **书键 = 文件路径哈希**（`'b' + textHash(path)`），而导入路径带时间戳（`book_<Date.now()>.pdf`）——**同一本书重新导入会得到新键，旧注解（墨迹/问答/进度/OCR/章节/索引）全部不可达**。目前只靠「从书架移除」时的级联清理避免残留。若要让注解随书走，书键应换成内容指纹（`LibraryView.fileHash` 已有「尺寸 + djb2 全字节」的实现，一次性成本可接受）。
