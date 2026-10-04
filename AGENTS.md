# AGENTS.md — YiBook（亦书）工程约定

鸿蒙平板上的「连续阅读」学习空间：PDF 长卷阅读 + 手写圈选提问 + 本地检索 + 云端 BYOK 作答。

## 产品文档（需求唯一来源）

位于 `F:\Markdown\亦书\`：《应用介绍.md》《使用体验描述.md》《问答管线设计.md》《调研报告.md》（含决策记录表）。改行为前先读对应章节；做完把偏离记入调研报告决策表。

## 工程原则

1. **不自研轮子**：遇到非平凡问题（算法/解析/编解码/协议），先去 GitHub / Gitee（OpenHarmony-SIG）/ OHPM 找现成开源方案，评估后引入或移植；确实没有才自己写。引入的库记录到《调研报告.md》。
2. **TDD 纵切**：一次一个行为，RED→GREEN→重构；测试走公共接口、描述行为而非实现。纯逻辑与 ArkUI 严格分离——`entry/src/main/ets/<域>/` 下的算法模块禁止 import `@ohos.*` 与 ArkUI，保证本地单测可跑。
3. **先跑通再优化**：性能问题先测（hilog 计时/Profiler），有数据再改。
4. 测试夹具放 `entry/src/test/fixtures/`（逻辑测试）与 `entry/src/main/resources/rawfile/`（应用运行时资源）。

## 工具链（本机）

- DevEco Studio：`F:\deveco\DevEco Studio\`
- node：`F:\deveco\DevEco Studio\tools\node\node.exe`（v24）
- hvigor（在工程根目录执行；**必须先设 SDK 环境变量**，否则报 00303217）：
  - `export DEVECO_SDK_HOME="F:\deveco\DevEco Studio\sdk"`
  - 版本：`node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" -v`
  - 本地单测：`node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default test`
  - 用例结果唯一凭据：`entry/.test/default/intermediates/test/coverage_data/test_result.txt`（守护进程日志不含 pass/fail）
  - 无设备编译验证（改 ArkUI/kit 相关代码后必跑）：`node "F:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleHap`
- SDK：HarmonyOS 6.1.1(24)（build-profile  compatibleSdkVersion）
- 测试框架：`@ohos/hypium`（本地单测在 `entry/src/test/`，入口 `List.test.ets` 的 `testsuite()` 注册；当前 31 个测试文件 / 88 用例）
- 真机部署：hdc 在 `F:\deveco\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`；一键脚本 `bash device-run.sh`（构建→安装→启动→hilog，`log` 参数只看日志）；`bash devtap.sh "<文本>" [dy]` 按文本定位组件点按（真机冒烟）。前置：DevEco 里 File > Project Structure > Signing Configs 勾选 Automatically generate signature——真机 profile 绑定「包名+设备 UDID」，OpenHarmony 自签材料不适用于华为商用平板。包名 `com.leaif.yibook`，测试平板 TGR-W10。
- 双 agent 协作边界：UI 视觉由独立 agent 负责（LibraryView/Index/StudyRoomView 等界面文件）；功能/管线归本工程。改共享文件前先 `ls -lt entry/src/main/ets/**` 确认对方已静默 ≥2 分钟，部署前同样，避免把半成品打进包。
- 书写交互铁律（用户定调，无可妥协）：**手指永远滚动、只有触控笔才书写**——PageInkCanvas 用 `touches[i].sourceTool === SourceTool.Pen` 过滤（SDK TouchObject.sourceTool 可用，此前误判不可用）；笔的颜色/粗细配置放阅读之外（配好再进来），橡皮擦放阅读之内——UI 侧约定。

## 已定决策（摘要，详见调研报告决策表）

- 锚点基准：PDF 原始页坐标 bbox + 文本层字符偏移双保险；裁白边只是视口变换。
- 已读判定：高水位线（到达过的最大页码），设置可手调。
- 视觉：夜城风（扁平矢量+波普+Lo-fi）——深藏蓝 #101E33 夜底 / 亮橙 #FF8A2A 唯一暖光（交互+AI）/ 纯黑硬阴影，素材为仓库内程序化 SVG（gen_night_assets.py）；详见调研报告决策 #37。
- 一期范围：原生 PDF、鸿蒙平板、BYOK、AGC（账号+云备份+Crash）零自建服务端。
- 检索：FTS5(jieba) BM25 + sqlite-vec 双路 → RRF → MMR top-6；LLM 只做作答与建书摘要。
- 长卷画布必须分块（CHUNK_MAX_VP=1500）：单 Stack 高超 GPU 纹理上限（约 4096-16384px）会**静默整块不渲染**（24 页教材 16377vp 全空白且日志无错，2 页样张 1644vp 恰好低于限值而漏判）。
- pdfService 的 getPagePixelMap 必须立即拷贝为独立 PixelMap（readPixelsToBuffer→createPixelMap，顺带 alpha 压平成白底）：文本页常为透明底叠深色画布不可见；严禁 writeBufferToPixels 回写（会损坏显示通道）。
- 开书先渲染后分析：只探测第 0 页定纵横比立即出首帧；整书版式（裁剪）分析转后台分批让出 UI 线程，进度显示在索引按钮。

## 实验素材

- `entry/src/main/resources/rawfile/sample_scan.pdf`：2 页扫描手写件（无文字层）——渲染/裁白边/连续滚动验证。
- `entry/src/main/resources/rawfile/sample_textbook.pdf`：《深入浅出程序设计竞赛（基础篇）》前 24 页书样（594×840pt）。**原书实为扫描版**：无文字层（M4 检索不可用，走二期 OCR 管线）、书签为逐页垃圾书签（已因此给 ChapterModel 加了垃圾书签防御：标记密度 > 页数一半视为无目录）。完整原书在 `F:\Leaif\书柜\`，勿入 rawfile（70MB）。
- 文本锚定/章节提取的真验证仍需**带文字层+真书签的原生 PDF**。
- `Notes_extracted/`：华为官方 Notes 模板 v1.0.5（Pen Kit 集成范例在 `components/richeditor`，勿直接引入 product/phone）。
