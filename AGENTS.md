# AGENTS.md — YiBook（亦书）工程约定

鸿蒙平板上的「连续阅读」学习空间：PDF 长卷阅读 + 手写圈选提问 + 本地检索 + 云端 BYOK 作答。

> **代码怎么组织**见 `ARCHITECTURE.md`：8 个业务域的职责边界、实测依赖方向、分层铁律、三条主数据流、以及「新增代码放哪里」的决策表。改动涉及跨域依赖或新建模块前先看它。

## 产品文档（需求唯一来源）

位于 `F:\Markdown\亦书\`：《应用介绍.md》《使用体验描述.md》《问答管线设计.md》《调研报告.md》（含决策记录表）。改行为前先读对应章节；做完把偏离记入调研报告决策表。

## 工程原则

1. **不自研轮子**：遇到非平凡问题（算法/解析/编解码/协议），先去 GitHub / Gitee（OpenHarmony-SIG）/ OHPM 找现成开源方案，评估后引入或移植；确实没有才自己写。引入的库记录到《调研报告.md》。
2. **TDD 纵切**：一次一个行为，RED→GREEN→重构；测试走公共接口、描述行为而非实现。纯逻辑与 ArkUI 严格分离——`entry/src/main/ets/<域>/` 下的算法模块禁止 import `@ohos.*` 与 ArkUI，保证本地单测可跑。
3. **先跑通再优化**：性能问题先测（hilog 计时/Profiler），有数据再改。
4. 测试夹具放 `entry/src/test/fixtures/`（逻辑测试）与 `entry/src/main/resources/rawfile/`（应用运行时资源）。
5. **本地单测不能碰 `@kit`**：本地单测跑在主机上，实测**无法执行 `@kit` 文件 IO 与网络**（`writeJsonFile` 返回 `false`）。凡是要 IO 的编排逻辑，必须把依赖抽成 `core/Ports` 里的端口、由页面层注入具体实现，单测注入纯内存替身——范例见 `book/BookIndexer` 与 `entry/src/test/BookIndexer.test.ets`。判据要用正控制（`writeJsonFile(...) === true`），别用 `fileExists`：它 catch 掉一切异常返回 false，分不清「@kit 不可用」和「文件不存在」。

## 工具链（本机）

- DevEco Studio：`F:\deveco\DevEco Studio\`
- node：`F:\deveco\DevEco Studio\tools\node\node.exe`（v24）
- hvigor（在工程根目录执行；**必须先设 SDK 环境变量**，否则报 00303217）：
  - `export DEVECO_SDK_HOME="F:\deveco\DevEco Studio\sdk"`
  - 版本：`node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" -v`
  - 本地单测：`node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default test`
  - 用例结果唯一凭据：`entry/.test/default/intermediates/test/coverage_data/test_result.txt`（守护进程日志不含 pass/fail）
  - 无设备编译验证（改 ArkUI/kit 相关代码后必跑）：`node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleHap`
  - 真机插桩测试（ohosTest，验 `@kit` 能力——如 PDF 文字层/书签：本地单测跑不了 `@kit`，这类验证只能上真机）：
    1. 临时回填签名：`cp .signing-config.backup.json5 build-profile.json5`
    2. 构建：`node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleHap`，再 `... --mode module -p module=entry@ohosTest -p product=default assembleHap`
    3. 安装：`hdc install -r entry/build/default/outputs/default/entry-default-signed.hap`；`hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap`
    4. 运行（**平板必须先解锁**，锁屏会报 `10106102`）：`hdc shell "aa test -b com.leaif.yibook -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 180000"`
    5. **用完必须还原**：`git checkout HEAD -- build-profile.json5`（否则签名口令会被提交）
- SDK：HarmonyOS 6.1.1(24)（build-profile  compatibleSdkVersion）
- 测试框架：`@ohos/hypium`（本地单测在 `entry/src/test/`，入口 `List.test.ets` 的 `testsuite()` 注册；当前 38 个测试文件 / 160 用例）
- 真机部署：hdc 在 `F:\deveco\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`；一键脚本 `bash device-run.sh`（构建→安装→启动→hilog，`log` 参数只看日志）；`bash devtap.sh "<文本>" [dy]` 按文本定位组件点按（真机冒烟）。前置：DevEco 里 File > Project Structure > Signing Configs 勾选 Automatically generate signature——真机 profile 绑定「包名+设备 UDID」，OpenHarmony 自签材料不适用于华为商用平板。包名 `com.leaif.yibook`，测试平板 TGR-W10。
- **真机崩溃取证：`node tools/faultlog.mjs`**（抄自 Delsin-Yu/JustPDF 的 `.agents/skills/arkts-runtime-fix`，Apache-2.0，重写为无依赖单文件）。用途：应用启动即崩/闪退时，一条命令拿到 `Reason` / `Error name` / `Error message` / 调用帧。
  - 为什么需要它：`hdc shell cat /data/log/faultlog/...` **会被拒**（那是 shell 用户），但 **`hdc file recv` 按已知路径能拿**（走 hdc 守护进程权限）；文件名用 `hdc shell "hidumper -s 1201 -a '-p Faultlogger -LogSuffixWithMs'"` 列。
  - 用 Node 而不是 `.ps1`：**本机执行策略会拒绝未签名的 `.ps1`**（脚本连 `-File` 都跑不起来），且 `pwsh` 不在 PATH 上。
  - 落盘目录 `faultlog/` 已加入 `.gitignore`（含设备信息）。
- 双 agent 协作边界：UI 视觉由独立 agent 负责（`entry/src/main/ets/view/` 下的 LibraryView/ReaderView/StudyRoomView、`ink/PageInkCanvas`、`pages/Index`）；功能/管线归本工程。**注：2026-10-04 已把源码从扁平的 `reading/` 拆为 8 个业务域，界面文件路径变为 `view/`（详见 `ARCHITECTURE.md`）**。改共享文件前先 `ls -lt entry/src/main/ets/**` 确认对方已静默 ≥2 分钟，部署前同样，避免把半成品打进包。
- 书写交互铁律（用户定调，无可妥协）：**手指永远滚动、只有触控笔才书写**——PageInkCanvas 用 `touches[i].sourceTool === SourceTool.Pen` 过滤（SDK TouchObject.sourceTool 可用，此前误判不可用）；笔的颜色/粗细配置放阅读之外（配好再进来），橡皮擦放阅读之内——UI 侧约定。

## 已定决策（摘要，详见调研报告决策表）

- 锚点基准：PDF 原始页坐标 bbox + 文本层字符偏移双保险；裁白边只是视口变换。
- 已读判定：高水位线（到达过的最大页码），设置可手调。
- 视觉：夜城风（扁平矢量+波普+Lo-fi）——深藏蓝 #101E33 夜底 / 亮橙 #FF8A2A 唯一暖光（交互+AI）/ 纯黑硬阴影，素材为仓库内程序化 SVG（gen_night_assets.py）；详见调研报告决策 #37。
- 一期范围：原生 PDF、鸿蒙平板、BYOK、AGC（账号+云备份+Crash）零自建服务端。
- 检索：FTS5(jieba) BM25 + sqlite-vec 双路 → RRF → MMR top-6；LLM 只做作答与建书摘要。
- 长卷画布必须分块（CHUNK_MAX_VP=1500）：单 Stack 高超 GPU 纹理上限（约 4096-16384px）会**静默整块不渲染**（24 页教材 16377vp 全空白且日志无错，2 页样张 1644vp 恰好低于限值而漏判）。
- **`Scroll.onScroll` 的入参是「相对上一帧的增量」，不是绝对滚动位置**（2026-10-04 实证定位）：曾把它当位置用（`this.scrollY = yOffset`），scrollY 恒为 1.2~2.0vp → 渲染窗口永远算在 y≈0 → **整本书只能看第一页、往下一片空白、页码恒为 P1**。真机取证：`onScroll` 里同时打印该入参与 `scroller.currentOffset().yOffset`，后者 3.2→6.0→10.4→16.0…而前者恒为差值 2.8/4.4/2.0/1.6。取值口径统一走 `pdf/RenderWindow.absoluteScrollOffset`（以容器上报为准，仅在容器报不出位置时退回增量累加），有单测 + 突变验证守着。**同轮还确认：`uitest uiInput swipe/fling/drag/dircFling` 在本机不会产生滚动**（连几何已验证正确的 `List+24×700` 都纹丝不动，`uitest` 只回 "No Error"），所以**手势类结论不能用它取证**——只有真手指或 `InputKeyFlow` 日志（能看到 `PanRecognizer` 归属）算数。
- 纯阅读时零逐帧状态写入：`refreshWindow` 只在渲染窗口真的变化时才重算 `visibleChunks`（键一变就重挂整块 PageInkCanvas，打断书写且卡顿）；`scrollY` 只在**有气泡要跟随内容**时才逐帧写。
- 裁白边＝**整本书一个框、四条边各自稳健估计**（`pdf/AutoCrop`，13 用例）：Otsu 自适应阈值 → 行/列投影（窗口**计数**抑制噪点，均值会被单行尖峰拉爆）→ 每条边取分位数（`edgeQuantile=0.25`＝只裁到 75% 页都同意的空白）→ 四分位距当一致性闸门（太散就不裁）→ `maxTrim` 夹住单边≤25%。**四条边必须独立**：实测该扫描件顶边近半页有墨、左右边距却一致，四边联合判定会互相否决到「一页都裁不了」。结果按书落盘 `crop_<key>.json`，二次开书直接读回。**不要退回"按奇偶取并集"**——并集对离群页零抵抗，少数出血页会把全书框拽到页边。
- **Pen Kit 的手写组件：能用，但必须按设备侧 HSP 版本选符号（2026-10-04 实测）**：华为官方 Notes 模板（`Notes_extracted/components/richeditor`）的墨迹层不是自绘 Canvas，而是 `@kit.Penkit` 的 `HandwriteComponent` + `HandwriteController`（`PenType`: PEN/BALLPOINT_PEN/PENCIL/MARKER/HIGHLIGHTER_BRUSH/MOSAIC/RUBBER/LASSO/LASER；`hiddenTools: HiddenConfig` 可裁掉内置工具与转盘；控制器只有 `save/load/onLoad/getContentRange/getThumbnail/scrollTo`，**没有设颜色的 API**，`PenHspInfo` 只有 penType/penWidth）。SDK 里确实有它（**在 HMS 侧**：`sdk\default\hms\ets\api\@hms.stylus.HandwriteComponent.d.ets`，注意是 `.d.ets` 不是 `.d.ts`，按 `*.d.ts` 搜会漏）。
  **根因（2026-10-04 从真机 jscrash 原文读出，推翻了此前的猜测）**：不是设备缺包，是**符号版本不匹配**。崩溃日志第 25 行原文——
  `the requested module 'com.huawei.hmos.hwstylusfeature/Penkit/ets/hsp/HandwritePaint' does not provide an export name 'HiddenToolType' which imported by '&.../PenProbe&'`
  → 模块**能被找到并加载**，但设备侧 HSP 是 `5.0.0(12)`，没有 SDK `.d.ets` 里标着 `@since 6.0.0(20)`/`6.1.0(23)` 的新符号（`HiddenToolType`/`HiddenConfig`）；`hiddenTools` 属性同理。**去掉这两个新符号后不再报符号错**——所以「换系统手写组件」这条路没有死在符号上，只是不能用比设备新的 API。教训：SDK 声明头里的 `@since` 必须逐个核对设备版本。
  **但它在初始化时又卡住了（下一道坎，已定位）**：只 import 核心四符号后，栈是这样——`HandwriteController` → `HspPaintController` → `PaintController.initOption` → `initPaintView (penkit|penkit|1.0.0|src/main/ets/hsp/HspPaintController.ts:15)`，报 `TypeError: Cannot read property createSystemHspModuleResourceManager of undefined`。同段日志里 Pen Kit 的子模块全部加载成功（`Penkit/{logger,brushengine,instantshape,prediction,penkitnative}`、`PencilEngineNative: Init[216] PenKit`），**说明 HSP 完全可用、是它内部拿不到「系统 HSP 资源管理器」**。关键：`createSystemHspModuleResourceManager` **不在 SDK 任何公开 `.d.ts`/`.d.ets` 里**，是 Pen Kit 内部调用的私有能力，**外部无法修补**。
  已排除的因素：①不是构造时序——华为样例也是字段初始化 `@Param handwriteController = new HandwriteController()`（`RichEditorArea.ets:45`），与我一致；②不是清单声明——样例 **19 个 module.json5 里没有一个**出现 `dependencies`/`hwstylus`/`Penkit`/`syscap`，它就是直接 import。
  因此剩下的可能只有「**签名/权限档位**」：系统 HSP 的资源管理器通常只对**系统应用或持受限权限**的应用注入，而我们是自签 debug 档（日志可见 `Hap type ... o:r:debug_hap:s0`）。**下一步唯一值得试的**：用 AGC 正式证书 + 开通 Pen Kit 能力的 profile 重签再跑（需要你的华为开发者账号），否则在本机停留于「HSP 可用但初始化被拒」。
  **⚠️ 曾被 `bm dump -a | grep stylus` 的 0 命中误导**：HSP 不出现在 bundle 列表里，`bm dump` 查不到 ≠ 运行时不可用，**不能据此断言设备缺件**。
  **顺带记下取崩溃原文的正确姿势**（`hdc shell cat/ls /data/log/...` 会被拒，因为那是 shell 用户）：
  `hdc shell "hidumper -s 1201 -a '-p Faultlogger -LogSuffixWithMs'"` 列文件名 → `hdc file recv /data/log/faultlog/faultlogger/<name> <local>` 拉全文（走 hdc 守护进程权限）。本轮两次崩溃都是靠它才读到真因。
- **提高渲染 DPI：在 API 24 + 本机上做不到（2026-10-05 带正控制实测，别再重试 pdfService 这条路）**
  - 动机有实测支撑：`getPagePixelMap()` 默认出图 ≈2px/pt（594×840pt 的页 → **1191×1684px**），而屏幕槽位宽 1840px → 被放大 **1.54×**，正文发虚。
  - **独立 spike（`pages/DpiProbe`，逐组报「输出尺寸 + 暗像素占比」，并带正控制）的最终矩阵**：
    - `getPagePixelMap()` → 594×840，**dark=9.80%** ← **正控制：有内容，说明测量管线可信**
    - `getAreaPixelMapWithOptions(m,w,h,options)` → 594×840，dark=**0.00%**
    - `getAreaPixelMapWithOptions(m,w,h)`（不带 options）→ 594×840，dark=**0.00%**
    - `getAreaPixelMap(m,w,h,false,false)`（@since 5.0.0(12) 五参旧版）→ 594×840，dark=**0.00%**
    - 上述 area 家族 + 裁框 + `bitmap=1840` → 1840×3025，dark=**0.00%**（尺寸被兑现，内容全白）
    - `getCustomPagePixelMap(m,false,false)` → **返回 undefined**（`Cannot read property getImageInfo of undefined`）
  - 覆盖过的变量：三种 matrix 语义（① width/height 当裁剪宽 ② 按比例放大 x/y/width/height ③ 按 d.ts 文档把 width/height 当**缩放倍率**）、带/不带 `PixelOptions`、两个 API 版本、多种 x/y 偏移。**结论：本机 pdfService 的非默认渲染入口一律产出空图。**
  - 另外两条路也已排除：`getPixelMapWithPages` 是 **`@since 26.0.0`**（本机 API 24 够不着，和端侧超分 `imageSuperResolution` 同一坑）；**整个 `pdfservice.d.ts` 里没有任何含 scale/dpi/zoom 的成员**，`PdfDocument` 只有 load/save/create/getPageCount/getPage。
- **⭐ `PdfView` 系统 PDF 视图组件：本机实测可用，是清晰度+流畅度的正解（2026-10-05 spike）**——比 pdfService 逐页取图好一整代。
  - 入口：从**已在用的** `@kit.PDFKit` 导出 —— `import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';`（不必引新 kit）。`@since 5.0.0(12)`。
  - 组件极简：`PdfView({ controller, pageLayout: pdfService.PageLayout.LAYOUT_SINGLE, isContinuous: true, showScroll: true, pageFit: pdfService.PageFit.FIT_PAGE })`。
  - `PdfController`：`loadDocument(path, password?, initPageIndex?, onProgress?)` / `registerScrollListener(cb)` / `getPagePixelMap(pageIndex, isSync?)` / `setViewOffset` / `enablePageDrag` / `setHighlightRects` / `releaseDocument`。
  - **真机实测（临时页 PdfViewProbe，用完已删）**：不崩溃；`registerScrollListener` 注册成功；`loadDocument` 返回 `code=0`；`getPagePixelMap(0)` 给 300×424px（预览尺寸）；**`PdfView` 以设备分辨率清晰渲染并连续滚动**（截图可见页脚「005 ◀」与下页「1.2 简单数学运算」，文字锐利）。
  - 滚动回调 `ScrollParam` 实测值：`off=(0.0,0.5) pdf=1374x46882 view=1810x2382` —— **offsetX/offsetY 是绝对偏移**（不是增量！），并同时给出 pdf/view 尺寸，屏幕↔页面坐标映射可直接推出来。
  - 于是它一次性解决了三件事：① 设备分辨率的清晰渲染（= 我们在 pdfService 上失败的目标）② 连续滚动（`isContinuous`，系统实现）③ 绝对滚动位置（绕开 `onScroll` 增量陷阱）。
  - **要迁移的话，代价与取舍必须明说**：`PdfView` 接管视口，**它没有裁剪 API**（我们那套 AutoCrop 去白边在它这里用不上）；现有依赖自有布局的功能（章节跳转、高水位进度、气泡按页锚定、裁白边变换、墨迹锚点）都要按它的坐标系重映射；墨迹层要改成**盖在 PdfView 之上**的覆盖层，并用 `ScrollParam` 做屏幕↔页面的坐标换算。属架构级改动，需用户拍板。
  - 注意 `getPixelMapWithPages` 仍是 `@since 26.0.0`（与端侧超分同坑），但 `PdfView` 已经能从别的角度解决同一问题。
  - 判断这类 API 是否真能用，**必须带正控制**（本次靠 `getPagePixelMap` 的 9.80% 才敢下"是 API 坏、不是我参数错"的结论）。
- **构建陈旧陷阱（2026-10-05 踩了并因此得出过一次假结论）**：`hvigorw assembleHap` 可以打印 `BUILD SUCCESSFUL` 却**没有重新打包 HAP**（`CompileArkTS` 跑了但 `PackageHap/SignHap` 因判 UP-TO-DATE 跳过），于是"我装了新包"是假的——实测因此误判「回退后仍全白」。
  - 核实手段：看 `entry/build/default/outputs/default/entry-default-signed.hap` 的 **LastWriteTime**；可疑时先 `Remove-Item -Recurse -Force entry/build` 再构建。
  - 判断设备上跑的是哪版：用**只有新版才有的日志**做指纹（本次靠 `targetW=` 字样认出装的是旧包）。
- 开书先渲染后分析：只探测第 0 页定纵横比立即出首帧；整书版式（裁剪）分析转后台分批让出 UI 线程，进度显示在索引按钮。
- 失效书目（书单有条目、文件已不在设备）：**只因成因说话**——文件不存在或 `PARSE_ERROR_FILE` → 「这本书的文件已丢失/读不了」且**不给重试**（点了也是白点），指路回书房移除；格式不支持、要密码各有其文案；`PARSE_ERROR_HANDLER`/未知维持决策 #38 的通用失败态（「这本书暂时打不开」+ 重试）。书架在封面下标注「文件已丢失」，详情页主按钮由「开始阅读」换成「从书架移除」。**只标记不自动清理**——删书会级联清掉进度/墨迹/草稿/OCR/问答，是否放弃由用户决定。成因判定是纯逻辑（`pdf/OpenDiagnosis.ets`），改文案改映射都在那里改并补单测。详见决策 #42。

## 实验素材

- `entry/src/main/resources/rawfile/sample_scan.pdf`：2 页扫描手写件（无文字层）——渲染/裁白边/连续滚动验证。
- `entry/src/main/resources/rawfile/sample_textbook.pdf`：《深入浅出程序设计竞赛（基础篇）》前 24 页书样（594×840pt）。**原书实为扫描版**：无文字层（M4 检索不可用，走二期 OCR 管线）、书签为逐页垃圾书签（已因此给 ChapterModel 加了垃圾书签防御：标记密度 > 页数一半视为无目录）。完整原书在 `F:\Leaif\书柜\`，勿入 rawfile（70MB）。
- `entry/src/main/resources/rawfile/sample_native.pdf`：**带文字层 + 真书签的原生 PDF**，自《Go语言学习笔记》正文节选 20 页（第 0..19 页，约 485KB）——文本锚定与章节提取的真验证素材。书签已重映射：10 条解析为 8 个去重页 `[1,3,4,5,6,9,16,18]`（第 16 页有 3 条，验同页去重）。真机插桩测试见 `entry/src/ohosTest/ets/test/NativePdf.test.ets`。**已实测结论**（TGR-W10 / API 24，2026-10-04）：`@kit.PDFKit` 20 页全部读出文字（共 12420 字），书签页码与离线 pypdf 结果逐条吻合，`chaptersFromOutline` 切出 9 章且连续覆盖 0..19。**注意：这是版权书籍节选，不要再扩大页数，也不要提交完整原书。**
- `Notes_extracted/`：华为官方 Notes 模板 v1.0.5（Pen Kit 集成范例在 `components/richeditor`，勿直接引入 product/phone）。
