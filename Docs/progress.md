# Imaxe Progress

A long-term issue tracker. Work through items by priority; check them off or remove them when complete.

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
- [ ] P1 补充兼容样本：灰度/CMYK、自定义 ICC、16 位渐变与 HDR/浮点输入、复杂 GIF disposal。当前矩阵的通过范围见 [IMAGE_FIDELITY_PERFORMANCE_REPORT.md](IMAGE_FIDELITY_PERFORMANCE_REPORT.md)。

### 基础性能场景

- [x] 建立独立性能套件：七种格式的冷加载器打开、100%/4× 离屏画布首绘、30 次 5000×4000 大图请求、被 gate 阻塞的目录扫描；分别记录正确性和耗时。
- [x] 补充两个同时存在的 AppKit 窗口、40 帧 GIF、96 帧 GIF 代理预算和主动清空缓存后的等价重载。
- [ ] P1 实机补测：真实慢卷、应用进程冷启动、屏幕可见首帧、主线程停顿、稳定 RSS。`IMAXE_SLOW_VOLUME_IMAGE` 可指定真实慢卷样本，未设置时不产生该场景数据。

### Limited GitHub Distribution

- [x] Release 说明模板已包含实际最低系统版本、Apple Silicon / arm64、提交变更、安装和迁移说明；正式发布前继续审阅生成内容。
- [ ] Do not apply for an Apple Developer account: do not configure `Apple Development`, `Developer ID`, notarization, or stapling workflows.
- [x] README 与 Release 模板已说明 ad-hoc/Gatekeeper、Applications 安装步骤及 Apple 官方 Open Anyway 操作；未新增 Developer ID 或公证依赖。
- [ ] Verify download, extraction, and first launch on a Mac without a development environment.

### Sparkle Updates

- [ ] Add `SUFeedURL` after the GitHub Pages appcast is publicly available, then verify an update from a lower `CFBundleVersion` using the published feed and Release assets.
- [x] 2026-10-19：确认公开仓库、匿名下载历史 ZIP，并启用 Pages 的 Actions 发布来源；`SUFeedURL` 与初始空 feed、部署工作流已准备。线上 XML 仍需主分支首次部署。
- [x] 现有 Keychain 公钥匹配 SUPublicEDKey，实际签名通过，修改内容与错误公钥被拒绝；没有导出或更换私钥。
- [x] 发布流程已加入产物摘要/EdDSA/包内元数据校验、固定提交、线上 feed 与已发布 manifest 构建号比较、draft 资产回读及一致产物恢复逻辑；不再自动切分支或覆盖不匹配资产。
- [x] 发布脚本在首次 Xcode 调用前取得构建/发布共用的原子目录锁；锁冲突不触发清理，构建/发布冲突、失败重试和终止释放回归通过。
- [x] 更新设置持续观察 Sparkle 的检查、下载与 allowsAutomaticUpdates；默认与禁用下载配置的状态同步测试通过。
- [x] 实际归档发现并修复通用二进制问题：发布显式使用 `ARCHS=arm64`，本地真实 ZIP 的架构、版本、feed、公钥、appcast 和深层代码签名均通过校验。
- [x] 匿名检查实际 v1.0.0 ZIP：包内为 1.0 (4)、最低 macOS 14.0，无 Sparkle/feed/公钥，确认需要先手动迁移一次。
- [x] 单元和 UI 测试增加仅测试启动参数，停用真实更新调度；设置单元测试仍使用独立的 Sparkle fixture 验证状态变化。
- [ ] 将已审查的 develop 变更合并 main，等待 Updates 工作流发布初始 feed，再匿名核验 HTTP 200 与 XML 内容；本轮未推送代码。
- [ ] 在干净 main 选择最终版本/构建号，运行完整 just build / just publish；实际验证中途上传恢复、Pages 失败恢复与匿名新资产下载。
- [ ] 使用两个正式打包构建完成 A/B 真实升级及第二台普通 Mac 的安装/迁移/授权验收。实施记录见 [AUTO_UPDATE_IMPLEMENTATION_2026-10-19.md](agents/AUTO_UPDATE_IMPLEMENTATION_2026-10-19.md)。

## P2 — Performance, Compatibility, and Experience

### Test Reliability

- [x] Replace timing-based metadata preload coverage with an explicit document-load gate so the session test remains deterministic under parallel test load.
- [x] Verify equivalent results across repeated image loads without requiring `NSCache` to retain document identity under memory pressure.
- [x] 保留原等价重载测试，并补充清空缓存后元数据、尺寸及实际渲染像素相等的测试；不依赖对象身份和自动淘汰时机。
- [x] 发布校验测试的编译与子进程等待移到后台，避免阻塞主线程；保持既有窗口断言和超时阈值不变，最终完整回归 109 项通过。

### Rendering and Performance

- [ ] Use Instruments to establish baselines for first visible preview time, peak RSS, and main-thread decoding across JPEG, PNG, TIFF, HEIF, WebP, GIF, and SVG.
- [ ] Confirm the bottleneck with data before introducing `CATiledLayer`; splitting into tiles while retaining full decoded frames is not sufficient.
- [ ] If tiled rendering is used, cap the tile cache, discard draw results from stale image generations, and verify the actual benefit.
- [ ] P2 长时间压力：真实前台多窗口、复杂长 GIF、系统内存压力、慢卷断开/恢复，记录内存趋势、卡顿与结果正确性。主动清空 NSCache 和离屏窗口测试不能替代这些实机验收。

### 本轮复核发现

- [ ] 长 GIF 仍需测量并控制 ImageIO 转码及 AppKit 帧表示的临时内存；保留像素预算已经生效，进程峰值仍明显高于该预算，详见性能报告。
- [ ] 当前是固定分辨率代理；高倍缩放不会恢复来源细节，后续按性能证据决定是否按需提高分辨率。
- [ ] Xcode 27 / macOS 27 环境曾出现测试宿主连接前超时，重跑可恢复；若再次出现，保留 xcresult 诊断，不将未执行测试记录为通过。
- [ ] 编译仍提示 ImageCollectionView 泛型 Identifiable 的 actor 隔离警告，以及 ImageSession 原有 metadata task 的 weak capture 警告；本轮未改动这些路径。

## References

- [CGImageSourceCreateThumbnailAtIndex](<https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)>)
- [kCGImageSourceShouldCacheImmediately](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately)
- [CATiledLayer](https://developer.apple.com/documentation/quartzcore/catiledlayer)
