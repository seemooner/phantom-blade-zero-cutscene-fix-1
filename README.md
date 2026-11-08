# 影之刃零播片黑屏修复

本项目分发 Zypre 的 [Cutscene Blackscreen Fix](https://www.nexusmods.com/phantombladezero/mods/239) 1.4.2 版，帮助解决部分预录动画在 1440p 或更高分辨率下黑屏、画面停住但声音继续播放的问题。它尝试播放游戏自带的 1080p 视频副本，游戏画面仍使用原有分辨率；受影响的播片清晰度会降低。实际效果取决于问题原因。

## 安装

1. 退出游戏并备份存档。若已安装 UE4SS，请先备份现有模组和设置，避免覆盖其他模组。
2. 从 [KintaroModding 发布页](https://github.com/KintaroModding/ue4ss/releases/tag/v3.0.1-1195-g1ceefac8)下载 `phantombladezero_ue4ss_v3.0.1-1195-g1ceefac8.zip`，按发布页说明将加载器放入 `PBZ/platform/steam/`。确认 `dwmapi.dll` 与 `ue4ss` 文件夹和 `PBZ.exe` 同级。
3. 在本仓库选择 **Code → Download ZIP**，解压，将 `CutsceneFix` 文件夹复制到 `PBZ/platform/steam/ue4ss/Mods/`。确认其中包含 `enabled.txt`、`scripts/main.lua` 和 `scripts/pbz_menuconfig.lua`。
4. 启动游戏，测试先前有问题的动画。如果仍异常，退出游戏后查看 `PBZ/platform/steam/ue4ss/UE4SS.log` 中的 `[CutsceneFix]` 信息。

Steam 用户可在游戏库中右键游戏，选择「管理 → 浏览本地文件」打开 `PBZ` 目录。本项目不包含 UE4SS 本身。加载器包可能附带其他默认启用的模组，请自行检查 `ue4ss/Mods/mods.txt` 和 `mods.json`。

## 验证与限制

在 Windows 11、RTX 4080 Laptop GPU、Steam build 26367565、UE4SS 1195 的一套设备上，日志确认 `3DCG_C07_MoBao.mp4` 已切换到 1080p 副本并开始播放；使用者确认先前导致退出的同一段动画正常播放且未退出。此前的旧版修订脚本在同一游戏版本播放时曾发生一次退出，原因未能最终确认。其他动画、显卡、系统及后续游戏更新尚未逐一验证；若出现黑屏或崩溃，请卸载补丁并按游戏原有设置排查。

作者 1.4.2 的更新说明指出，它避免跨帧保留游戏视频播放器对象，以降低对象销毁后访问导致的崩溃风险；这与本次现象相符，但不能证明其为本次唯一原因。可能存在音画同步偏差，可参照作者说明调整 `Resync`。

## 卸载

退出游戏后移走 `PBZ/platform/steam/ue4ss/Mods/CutsceneFix` 文件夹。如果还有其他模组使用 UE4SS，请保留加载器；否则按加载器发布页说明卸载。

## 版本、来源和致谢

补丁由 **Zypre** 制作，原始页面及转载条款见 [Nexus Mods](https://www.nexusmods.com/phantombladezero/mods/239)。本次使用的 1.4.2 压缩包来自 [Playbuff 镜像](https://www.playbuff.net/mod/phantombladezero/cutscene-blackscreen-fix.html)，SHA-256 为 `10e135630e71721a9b3e744a1618dcc60c2d5759ff1b5b2aac23969d26bca8a8`；该值与镜像列示一致，但未能与作者官方包的哈希交叉核对。作者随包说明保存在 `UPSTREAM_README.txt`。

UE4SS 由 [UE4SS-RE 与贡献者](https://github.com/UE4SS-RE/RE-UE4SS)开发，游戏适配包由 [KintaroModding](https://github.com/KintaroModding/ue4ss)发布。游戏及视频内容属于各自权利人，本仓库不包含游戏资源。

`changes.diff` 是此前社区修订版的历史差异，**不描述目前的作者 1.4.2**；旧脚本另保存在 `archive/`。1.4.2 是作者原版，与此前的社区修订不是同一套实现，也未运行此前针对旧脚本编写的 13 项模拟测试。
