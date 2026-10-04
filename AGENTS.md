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
- **Pen Kit 的手写组件在本机运行不了（2026-10-04 spike 实测，别再盲试）**：华为官方 Notes 模板（`Notes_extracted/components/richeditor`）的墨迹层不是自绘 Canvas，而是 `@kit.Penkit` 的 `HandwriteComponent` + `HandwriteController`（`PenType`: PEN/BALLPOINT_PEN/PENCIL/MARKER/HIGHLIGHTER_BRUSH/MOSAIC/RUBBER/LASSO/LASER；`hiddenTools: HiddenConfig` 可裁掉内置工具与转盘；控制器只有 `save/load/onLoad/getContentRange/getThumbnail/scrollTo`，**没有设颜色的 API**，`PenHspInfo` 只有 penType/penWidth）。SDK 里确实有它（**在 HMS 侧**：`sdk\default\hms\ets\api\@hms.stylus.HandwriteComponent.d.ets`，注意是 `.d.ets` 不是 `.d.ts`，所以按 `*.d.ts` 搜会漏），**编译完全通过**——但真机上只要 `import { HandwriteComponent } from '@kit.Penkit'` 就会让应用启动即崩：`Reason:SyntaxError`（jscrash，`/data/log/faultlog` 无读权限）。二分对照：同页去掉该 import 后正常加载。**根因已查明（不是我们的代码、不是权限、不是签名、不是 API 版本）**：声明头写着 `@syscap SystemCapability.Stylus.Handwrite` / `@since 5.1.0(18)`（我们用 API 24，够）/ 实现归属 `@bundle com.huawei.hmos.hwstylusfeature/.../HandwritePaint`——**实现在华为的系统 HSP 里，而这台 TGR-W10 的 ROM 根本没装它**：`bm dump -a` 共 204 个包，`stylus`/`hwstylusfeature` 命中 **0**（同表 `thememanager` 命中 1，证明是全量 grep）。所以是**设备/ROM 能力缺失**：声明在 SDK 里，运行时不在机器上。**要再试的前置**：先确认设备侧存在 `com.huawei.hmos.hwstylusfeature`，或运行时 `canIUse('SystemCapability.Stylus.Handwrite')` 为 true；否则换任何写法都会崩。
- 开书先渲染后分析：只探测第 0 页定纵横比立即出首帧；整书版式（裁剪）分析转后台分批让出 UI 线程，进度显示在索引按钮。
- 失效书目（书单有条目、文件已不在设备）：**只因成因说话**——文件不存在或 `PARSE_ERROR_FILE` → 「这本书的文件已丢失/读不了」且**不给重试**（点了也是白点），指路回书房移除；格式不支持、要密码各有其文案；`PARSE_ERROR_HANDLER`/未知维持决策 #38 的通用失败态（「这本书暂时打不开」+ 重试）。书架在封面下标注「文件已丢失」，详情页主按钮由「开始阅读」换成「从书架移除」。**只标记不自动清理**——删书会级联清掉进度/墨迹/草稿/OCR/问答，是否放弃由用户决定。成因判定是纯逻辑（`pdf/OpenDiagnosis.ets`），改文案改映射都在那里改并补单测。详见决策 #42。

## 实验素材

- `entry/src/main/resources/rawfile/sample_scan.pdf`：2 页扫描手写件（无文字层）——渲染/裁白边/连续滚动验证。
- `entry/src/main/resources/rawfile/sample_textbook.pdf`：《深入浅出程序设计竞赛（基础篇）》前 24 页书样（594×840pt）。**原书实为扫描版**：无文字层（M4 检索不可用，走二期 OCR 管线）、书签为逐页垃圾书签（已因此给 ChapterModel 加了垃圾书签防御：标记密度 > 页数一半视为无目录）。完整原书在 `F:\Leaif\书柜\`，勿入 rawfile（70MB）。
- `entry/src/main/resources/rawfile/sample_native.pdf`：**带文字层 + 真书签的原生 PDF**，自《Go语言学习笔记》正文节选 20 页（第 0..19 页，约 485KB）——文本锚定与章节提取的真验证素材。书签已重映射：10 条解析为 8 个去重页 `[1,3,4,5,6,9,16,18]`（第 16 页有 3 条，验同页去重）。真机插桩测试见 `entry/src/ohosTest/ets/test/NativePdf.test.ets`。**已实测结论**（TGR-W10 / API 24，2026-10-04）：`@kit.PDFKit` 20 页全部读出文字（共 12420 字），书签页码与离线 pypdf 结果逐条吻合，`chaptersFromOutline` 切出 9 章且连续覆盖 0..19。**注意：这是版权书籍节选，不要再扩大页数，也不要提交完整原书。**
- `Notes_extracted/`：华为官方 Notes 模板 v1.0.5（Pen Kit 集成范例在 `components/richeditor`，勿直接引入 product/phone）。
