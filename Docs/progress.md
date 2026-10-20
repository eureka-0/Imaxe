# Imaxe Progress

A long-term issue tracker. Work through items by priority; check them off or remove them when complete.

## 当前发布范围与合并约定

- 本次目标为 1.1.0；正式构建号在发布准备 PR 中确定，合入 main 后从干净、与远端一致的 main 打包，保留 macOS 15.6+、arm64、ad-hoc 分发与现有更新签名密钥。
- 范围包括已有图片保真、加载预算与导航修复、Sparkle 设置同步、发布资产校验及 Pages feed；本轮补兼容样本和发布前验证，不引入分块渲染、按需恢复高分辨率或 HDR 显示承诺。
- 本轮 develop 收尾后通过 PR 合入 main，并由 GitHub 自动删除 develop；之后从最新 main 创建具体功能分支，通过 PR 合并后删除，不再保留长期 develop。
- 本轮 PR 建议使用 merge commit 保留已有开发历史；后续较小功能 PR 默认 squash merge。合并、推送、打标签和正式发布由用户安排。
- 不申请 Apple Developer 账号，不配置 Apple Development、Developer ID、公证或 stapling；这是分发约束，不是待实现任务。
- 用户已明确将真实慢卷测试降为低优先级待验收，本轮不下载新图片，使用仓库现有图片和本地生成样本。

## P0 — Critical Issues

## P1 — Stability and Core Experience

### Image Loading and Memory

- [x] 方向与透明边缘：加入 EXIF 1–8 的旋转、镜像角点渲染矩阵；验证 PNG 半透明颜色、透明区域和降采样边缘，SVG 验证透明区域。
- [x] ICC 与色彩显示：对 sRGB、Display P3 样本比较代理 ICC 数据和 AppKit 实际渲染的 RGB 值；信息面板优先显示来源 profile 名称。
- [x] DPI 与显示比例：保留来源 DPI，旋转 90° 后交换用于打印比例的 DPI 轴；验证 144×72 DPI 图片的物理尺寸，图片表示尺寸使用方向修正后的像素数。
- [x] 16 位代理：PNG、TIFF 代理验证通道位深、alpha 和非端点采样值；16 位输入的代理回退只使用 TIFF/PNG，禁止 JPEG/HEIC 回退。
- [x] 多页 TIFF：明确只显示第 0 页，保留容器总页数并在信息面板显示 `1 / N`；不同尺寸、不同内容的两页样本确认不会被 AppKit 选成替代表示。
- [x] GIF、TIFF 首页、SVG、静态位图使用独立策略边界；64 MiB 保留像素预算按位深和 GIF 帧数计算，最长边仍受 16384 限制。该预算不代表进程 RSS 上限。
- [x] GIF 代理保留帧数、帧时长和循环次数；有限循环停在末帧，无限循环继续播放，每窗口保留独立播放状态。
- [x] 图片提交不再等待目录扫描；用显式 gate 验证慢扫描、取消扫描和旧代次结果，目录扫描完成后再更新导航。
- [x] 发布候选兼容矩阵：灰度/CMYK JPEG 与 TIFF、自定义校准 ICC、PNG/TIFF 16 位渐变、32 位浮点 TIFF，以及手工编码的局部帧 GIF disposal 2/3；5 项测试覆盖 9 组输入，比较来源元数据、代理数据及实际 AppKit 渲染。测试位于 `ImaxeTests/ImageCompatibilityTests.swift`，不承诺未覆盖的 HDR 格式或屏幕输出。

### 基础性能场景

- [x] 建立独立性能套件：七种格式的冷加载器打开、100%/4× 离屏画布首绘、30 次 5000×4000 大图请求、被 gate 阻塞的目录扫描；分别记录正确性和耗时。
- [x] 补充两个同时存在的 AppKit 窗口、40 帧 GIF、96 帧 GIF 代理预算和主动清空缓存后的等价重载。
- [x] P1 本机基础场景：新增独立进程冷启动到首帧可响应的 3 次测量，以及文件选择器打开图片、可见画布 100%/连续放大、前台导航与窗口截图；UI 测试单独记录时间和 physical footprint，额外采集独立应用进程短段 RSS。Debug 基线不等同于正式 Release 包性能。
- [ ] P1 正式包性能补验：在合并后生成的 Release 候选上记录精确的图片可见首帧、主线程停顿分布及稳定 RSS；当前 AX 可见墙钟时间、短段 RSS 和离屏首绘不能替代这三项。

### Limited GitHub Distribution

- [x] Release 说明模板已包含实际最低系统版本、Apple Silicon / arm64、提交变更、安装和迁移说明；正式发布前继续审阅生成内容。
- [x] README 与 Release 模板已说明 ad-hoc/Gatekeeper、Applications 安装步骤及 Apple 官方 Open Anyway 操作；未新增 Developer ID 或公证依赖。
- [ ] Verify download, extraction, and first launch on a Mac without a development environment.

### Sparkle Updates

- [ ] 公开 feed 与真实升级验收：SUFeedURL 已配置，待初始 Pages 部署后验证公开 RSS，再从含 Sparkle 的较低 CFBundleVersion 通过正式 feed 和 Release 资产完成升级。
- [x] 2026-10-19：确认公开仓库、匿名下载历史 ZIP，并启用 Pages 的 Actions 发布来源；`SUFeedURL` 与初始空 feed、部署工作流已准备。线上 XML 仍需主分支首次部署。
- [x] 现有 Keychain 公钥匹配 SUPublicEDKey，实际签名通过，修改内容与错误公钥被拒绝；没有导出或更换私钥。
- [x] 发布流程已加入产物摘要/EdDSA/包内元数据校验、固定提交、线上 feed 与已发布 manifest 构建号比较、draft 资产回读及一致产物恢复逻辑；不再自动切分支或覆盖不匹配资产。
- [x] 发布脚本在首次 Xcode 调用前取得构建/发布共用的原子目录锁；锁冲突不触发清理，构建/发布冲突、失败重试和终止释放回归通过。
- [x] 更新设置持续观察 Sparkle 的检查、下载与 allowsAutomaticUpdates；默认与禁用下载配置的状态同步测试通过。
- [x] 实际归档发现并修复通用二进制问题：发布显式使用 `ARCHS=arm64`，本地真实 ZIP 的架构、版本、feed、公钥、appcast 和深层代码签名均通过校验。
- [x] 匿名检查实际 v1.0.0 ZIP：包内为 1.0 (4)、最低 macOS 14.0，无 Sparkle/feed/公钥，确认需要先手动迁移一次。
- [x] 单元和 UI 测试增加仅测试启动参数，停用真实更新调度；设置单元测试仍使用独立的 Sparkle fixture 验证状态变化。
- [ ] 将已审查的 develop 变更合并 main，等待 Updates 工作流发布初始 feed，再匿名核验 HTTP 200 与 XML 内容；本轮未推送代码。
- [ ] 最终版本/构建号通过发布准备 PR 合入 main，随后在干净 main 运行完整 just build / just publish；实际验证中途上传恢复、Pages 失败恢复与匿名新资产下载。
- [ ] 使用两个正式打包构建完成 A/B 真实升级及第二台普通 Mac 的安装/迁移/授权验收；旧版 1.0 (4) 不含 Sparkle，只用于手动迁移验收。

## P2 — Performance, Compatibility, and Experience

### Test Reliability

- [ ] PR #1 第三轮云端 CI（run `39416951796`，提交 `ecef102a`）：macOS 26、27 全部通过；macOS 15 再次在 `CompileAssetCatalogVariant` 崩溃，三个测试调用均为 0 项执行。已下载构建日志，确认 `AssetCatalogAgent-AssetRuntime` 连接中断并伴随 CoreMedia 覆盖运行时缺失符号；第二轮未复现不能证明资源编译问题已根治，浮点样本的新断言在 macOS 15 仍未得到执行证据。
- [x] macOS 15 CI 改为构建与执行分离：在 macOS 26 使用 Xcode 26.3 和 ad-hoc 签名构建完整应用、单元与 UI 测试产物，经 tar 保留权限、符号链接及签名后上传同一工作流；macOS 15 校验提交 SHA、源码路径和 Xcode 版本，再通过 `just test --test-without-building` 分别运行原有三个测试组。未删除 Icon Composer 图标、跳过失败用例或降低浮点样本断言；macOS 26、27 保留各自原生构建和测试。
- [x] 测试脚本增加 `--build-only` 与 `--test-without-building`，保留既有测试过滤及覆盖率导出；两个模式互斥，构建模式拒绝测试过滤或覆盖率报告，只执行模式要求恰好一份 `.xctestrun`。汇总检查同时要求预构建 job 与全部系统测试成功，产物恢复失败时禁止回退到 macOS 15 原生构建；PR/手动触发与 `fail-fast: false` 保持不变。
- [x] 构建与执行分离的本机验证：`just test --build-only` 成功；完整产物经 tar 打包、解包和两份应用 bundle 的深层签名校验后还原，分别通过 `--test-without-building` 执行其余单元、窗口和 UI 测试，结果为 96 通过/1 慢卷跳过、17 通过及 4 通过，合计 117 通过、0 失败、1 跳过。两组单元标识并集为原有 114 项且无交集，覆盖率正常导出，三个执行日志均无资源或 Swift 重新编译；结果为 `Build/TestResults/Imaxe-20261020-200250.xcresult`、`Imaxe-20261020-200332.xcresult`、`Imaxe-20261020-200402.xcresult`。本机仍为 macOS 27.0.1 / Xcode 27.1；参数互斥检查、SwiftLint、ShellCheck、shfmt、YAML/步骤语法和 actionlint 通过。
- [ ] 构建与执行分离后的云端验收：需在下一轮 PR CI 确认 macOS 15 能执行全部原有测试，尤其是浮点 TIFF 的来源/代理样本断言及 UI 测试；本机打包还原验证不能代替跨系统执行。macOS 15 上 Xcode 26.3 的原生资源编译稳定性继续保留为未解决的工具链边界，不纳入这条运行兼容性测试路径。
- [ ] PR #1 第二轮云端 CI（run `39414212147`）：macOS 26、27 全部通过；macOS 15 的资源编译、窗口套件和 UI 测试已通过，唯一失败为浮点 TIFF 的 `NSBitmapImageRep.colorAt` 蓝色分量断言（实际 1.0，期望 1.5）。需分别验证底层浮点样本与 AppKit 渲染，不以颜色访问接口的返回值直接证明代理像素被截断，也不降低超范围样本的验收要求。
- [x] 调整浮点 TIFF 验收取样：直接从 Core Graphics 解码图的 `dataProvider` 按行跨度、分量字节序和通道布局读取 Float32；来源 TIFF 与代理 TIFF 分别检查 `[0.25, 0.5, 1.5]`，容差仍为 0.001，保留 32 位/浮点标志、16 字节 RGBA 预算及 AppKit 实际渲染对照。不对 macOS 15 跳过或放宽断言；若底层样本确实被截断，仍会明确报告来源/代理及通道。
- [x] 浮点取样修复本机验证：默认 `just test --skip-ui --suite ImageCompatibilityTests --no-coverage` 覆盖 5 项测试、9 组输入，全部通过，结果为 `Build/TestResults/Imaxe-20261020-193734.xcresult`；Xcode 文件诊断、SwiftLint、ShellCheck、SwiftFormat 与 diff 检查通过。临时 CI 签名配置下的两次宿主启动挂起均已终止，未计入通过；macOS 15 的新断言仍待推送后云端复验。
- [x] PR #1 首轮云端故障阶段性复验：run `39393986174` 的 macOS 26 Xcode 工具链混用和 macOS 27 窗口同步测试超时，在第二、三轮均未再出现，26、27 整个任务通过。macOS 15 的资源编译及窗口/UI 测试曾在第二轮通过，但资源代理在第三轮再次崩溃；该问题继续单独跟踪，不将偶尔编译成功记为已根治。
- [x] 修正 CI 工具链选择：除 `DEVELOPER_DIR` 外，同步设置 runner 的 `xcode-select`、清除 xcrun 查找缓存，并通过 `TEST_RUNNER_DEVELOPER_DIR` 显式传给测试宿主；记录实际全局选择，避免子进程回到镜像默认 Xcode。第二轮已确认 macOS 15 资源编译及 macOS 26 发布校验通过。
- [x] 隔离窗口动画单元测试：`ImageViewTests` 使用 Swift Testing 的 `.serialized`，CI 通过 `--suite` / 新增 `--skip-suite` 分别启动窗口套件与其余单元测试；不再让图片解码、性能样本及发布 fixture 编译与窗口动画共用测试宿主，保留原有断言与超时阈值。零测试的编译失败也保留所有结果摘要和完整 build 日志，供资源代理问题复查。
- [x] CI 修复本机复验：窗口套件 17 通过，其余单元测试 96 通过、1 项慢卷跳过，均无失败，覆盖率正常导出；对比原云端单元测试标识，两组并集完整覆盖原 114 项且无交集。结果为 `Build/TestResults/Imaxe-20261020-190916.xcresult` 与 `Build/TestResults/Imaxe-20261020-191152.xcresult`；编译失败产物回放确认保留两份摘要和 build 日志，退出状态仍为失败。Xcode 文件诊断、SwiftLint、ShellCheck、SwiftFormat、shfmt、工作流静态检查及 diff 检查通过。
- [x] CI 修复后的本机 UI 复验：初次 `Build/TestResults/Imaxe-20261020-191250.xcresult` 在启用自动化模式时超时，未执行测试；当时只读检查显示本机自动化模式关闭且需要用户认证，未修改系统安全设置。随后重试 4 通过、0 失败，结果为 `Build/TestResults/Imaxe-20261020-191533.xcresult`；与两组单元测试合计 117 通过、0 失败、1 项慢卷跳过。此前本机两次宿主停在 dyld 文件打开阶段，均终止且未记为通过，保留旧派生目录后重建通过；三个云端组合仍需推送修复后重新验收。
- [x] 添加 GitHub Actions CI：仅对目标分支为 `main` 的 PR 及手动操作触发，不因 push 触发；ARM64 `macos-15` / `macos-26` 使用 Xcode 26.3，`xcode-27`（macOS 27）使用稳定版 Xcode 27.0，通过 `just test` 分别运行单元测试（含覆盖率）及完整 UI 测试。保持 `fail-fast: false`，收集三个系统的独立结果；临时配置所有测试目标的 ad-hoc 签名，不依赖开发证书，保存环境、日志、结果摘要和完整 xcresult 14 天。汇总 job 为 `macos_compatibility_gate`，检查名为 `macOS compatibility (unit + UI)`，矩阵全部成功后才通过。
- [x] CI 测试入口本机验证：使用与 CI 相同的临时签名配置分别运行测试，单元测试 113 通过、0 失败、1 项慢卷跳过，UI 测试 4 通过、0 失败，覆盖率报告正常导出。结果为 `Build/TestResults/Imaxe-20261020-155435.xcresult` 和 `Build/TestResults/Imaxe-20261020-155514.xcresult`；运行环境为本机 macOS 27.0.1 / Xcode 27.1，不代表三个云端组合已通过。
- [x] 三系统矩阵静态验证：YAML、触发事件、三个 runner / Xcode 配对、`fail-fast: false`、汇总依赖、全部 shell 步骤语法及 `git diff --check` 通过。actionlint 1.7.12 尚未内置官方 `xcode-27` 标签，使用仅允许此标签的临时配置后，CI 与既有 Updates 工作流均通过 actionlint；未关闭其他检查。
- [ ] CI 云端首轮验收：创建面向 main 的 PR 后检查三个系统及各自固定工具链的实际运行结果，尤其是 UI 自动化权限、原生文件选择器和测试宿主启动；手动触发入口需工作流先存在于默认分支。当前本机验证不能代替云端执行；成功后将 `macOS compatibility (unit + UI)` 加入 main ruleset 的 required status checks，原则上禁止直接 push，管理员 bypass 保持现有约定。
- [ ] CI 覆盖边界：runner 标签只固定系统大版本，不能证明恰好 macOS 15.6 的最低版本兼容；ARM64 矩阵不覆盖 Intel。慢卷保持显式跳过，云端启动/内存指标不作为正式包性能验收。
- [x] Replace timing-based metadata preload coverage with an explicit document-load gate so the session test remains deterministic under parallel test load.
- [x] Verify equivalent results across repeated image loads without requiring `NSCache` to retain document identity under memory pressure.
- [x] 保留原等价重载测试，并补充清空缓存后元数据、尺寸及实际渲染像素相等的测试；不依赖对象身份和自动淘汰时机。
- [x] 发布校验测试的编译与子进程等待移到后台，避免阻塞主线程；保持既有窗口断言和超时阈值不变，最终完整回归 109 项通过。
- [x] 2026-10-20 发布候选回归（路径输入修复后）：完整 `just test --no-coverage` 共 118 项，117 通过、0 失败、1 项真实慢卷因未配置样本而跳过；4 项 UI 全部通过。修改后的 UI 文件通过 SwiftFormat 与 SwiftLint 检查，`git diff --check` 通过。完整结果为 `Build/TestResults/Imaxe-20261020-153504.xcresult`。
- [x] UI 文件样本由测试入口复制到忽略的 Build 目录，使用原生文件选择器并等待对话框、路径输入框及打开按钮就绪；截图限定为应用窗口，避免高倍画布越界时捕获整个屏幕。原有窗口/动画断言及超时阈值未改动。

### Rendering and Performance

- [ ] 低优先级真实慢卷验收：待有外置盘或 NAS/网络挂载样本后验证读取与首绘。`IMAXE_SLOW_VOLUME_IMAGE` 未设置时没有实测数据；下载到内置 SSD 的图片和扫描 gate 都不能替代慢卷。本项按用户决定不阻塞本轮收尾。
- [ ] 扩展 HDR 兼容范围：HEIF/增益图、其他浮点容器及 HDR 屏幕亮度输出未覆盖；本轮仅验证 32 位浮点 TIFF 的样本保留、SDR AppKit 参考渲染和保守内存估算。
- [ ] 后续性能基线隔离：测试宿主仍会初始化开发配置的近期记录及缩略图；建立独立测试数据目录后再做可比的启动和 RSS 回归，不把本轮单次观测当作优化收益。
- [ ] Use Instruments to establish baselines for first visible preview time, peak RSS, and main-thread decoding across JPEG, PNG, TIFF, HEIF, WebP, GIF, and SVG.
- [ ] Confirm the bottleneck with data before introducing `CATiledLayer`; splitting into tiles while retaining full decoded frames is not sufficient.
- [ ] If tiled rendering is used, cap the tile cache, discard draw results from stale image generations, and verify the actual benefit.
- [ ] P2 长时间压力：真实前台多窗口、复杂长 GIF、系统内存压力、慢卷断开/恢复，记录内存趋势、卡顿与结果正确性。主动清空 NSCache 和离屏窗口测试不能替代这些实机验收。

### 本轮复核发现

- [x] 修复 UI 文件选择器路径输入：完整回归与 UI 单独重跑均复现逐键输入丢失字符；改用保存/恢复剪贴板的整段粘贴，并等待字段值匹配。若期间其他程序改写剪贴板，则保留较新的内容。
- [x] UI 路径确认补测：粘贴成功后曾观测到 Return 期间系统 `openAndSavePanelService` 在文本输入处理栈崩溃；改为等待并双击匹配完整路径的原生补全项。最终 UI 单独回归 4 项通过、0 失败，结果为 `Build/TestResults/Imaxe-20261020-153322.xcresult`；路径、打开结果、缩放和切换断言均保留。
- [x] 发布候选补测复现并修复 32 位浮点 TIFF 预算低估：代理尺寸与缓存估算共用按通道位深计算的 RGBA 成本，32 位每像素按 16 字节估算；浮点样本位深、超出 1.0 的通道值及 AppKit 参考渲染回归通过。
- [ ] 长 GIF 仍需测量并控制 ImageIO 转码及 AppKit 帧表示的临时内存；保留像素预算已经生效，既有测试宿主观测的进程峰值高于该预算，不能据此推断独立应用稳定 RSS。
- [ ] 当前是固定分辨率代理；高倍缩放不会恢复来源细节，后续按性能证据决定是否按需提高分辨率。
- [ ] Xcode 27 / macOS 27 环境曾出现测试宿主连接前超时，重跑可恢复；若再次出现，保留 xcresult 诊断，不将未执行测试记录为通过。
- [x] 将 ImageCollectionView 的状态与默认配置构造移入初始化器，独立创建 ImageSession 元数据任务；七处泛型隔离警告及一处 weak capture 警告已清除，Xcode 构建和文件诊断均无警告。
- [x] 合并 ImageCollectionView 中返回条件相同的连续 guard，保留原有短路判断顺序，SwiftFormat repeatedGuard 检查通过。

## References

- [CGImageSourceCreateThumbnailAtIndex](<https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)>)
- [kCGImageSourceShouldCacheImmediately](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately)
- [CATiledLayer](https://developer.apple.com/documentation/quartzcore/catiledlayer)
