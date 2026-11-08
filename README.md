# 影之刃零播片黑屏修复（社区修订版）

> **兼容性提示（Steam build 26367565）**：本仓库旧版脚本搭配 UE4SS 1195 时，有一次动画开始后报错退出的反馈，原因尚未确定，建议暂缓在此版本使用。作者的 1.4.2 更新提到修复播放器销毁后引用导致的崩溃；该版本正在本地测试，尚未证实解决本次问题，也尚未同步到本仓库。旧版 26266538 的使用反馈见下文。

针对《影之刃零》PC Steam 版在 1440p 或更高分辨率下，部分预录动画黑屏、声音与字幕正常、动画结束后画面恢复的问题。本修订版基于 Zypre 的 [Cutscene Blackscreen Fix](https://www.nexusmods.com/phantombladezero/mods/239)。

补丁尝试把符合条件的高编码级别 H.264 视频切换到游戏自带的低分辨率版本；游戏分辨率不变，被替换的视频画质会降低。问题原因可能不同，不能保证适用于所有黑屏。

## 下载与安装

1. 退出游戏，并备份游戏存档。
2. 从 [KintaroModding 发布页](https://github.com/KintaroModding/ue4ss/releases/tag/v3.0.1-1195-g1ceefac8) 下载 `phantombladezero_ue4ss_v3.0.1-1195-g1ceefac8.zip`。该游戏专用 UE4SS 1195 构建有社区报告支持 Steam build 26367565；其他 UE4SS 构建请核实兼容性。按该页面的安装说明，将压缩包内容解压到游戏的 `PBZ/platform/steam/` 文件夹；`dwmapi.dll` 和 `ue4ss` 文件夹应与 `PBZ.exe` 同级。已安装 UE4SS 的用户先备份现有模组和配置，并核实版本兼容性。
3. 在本仓库选择 **Code → Download ZIP**，解压后将 `CutsceneFix` 文件夹复制到 `PBZ/platform/steam/ue4ss/Mods/`。确认最终存在 `ue4ss/Mods/CutsceneFix/scripts/main.lua` 和 `enabled.txt`。
4. 启动游戏，在原有分辨率下重播异常动画。UE4SS 附带的其他模组是否启用取决于其配置；不需要时可按 UE4SS 说明禁用。

Steam 中可通过游戏属性 → 已安装文件 → 浏览定位 `PBZ` 文件夹。若动画仍黑屏，退出游戏后查看 `PBZ/platform/steam/ue4ss/UE4SS.log` 中的 `[CutsceneFix]` 行，确认补丁是否加载和是否发生重定向。

## 卸载

退出游戏后，从 `ue4ss/Mods/` 移走 `CutsceneFix` 文件夹即可禁用此补丁。如果不再需要 UE4SS，按其作者的安装页面说明卸载；若还有其他 UE4SS 模组，请保留加载器。不要用旧备份覆盖新的游戏进度。

## 修改与验证

修订版收紧媒体源匹配、避免改写无关属性、在打开失败或超时时恢复修改、延迟记录成功缓存，并增加诊断日志。完整变更见 `changes.diff`。13 个 Lua 模拟场景通过；在一台 RTX 4080 Laptop GPU、Windows 11、Steam build 26266538 的设备上，用户反馈解决了对应播片黑屏。Steam build 26367565 搭配 UE4SS 1195 已验证游戏启动、脚本加载和媒体打开钩子注册，实际动画播放仍需验证；其他配置及所有过场动画尚未逐一验证，音画同步仍可能受影响。

## 致谢与许可

原补丁作者 **Zypre**，见 [原始补丁页面与转载条款](https://www.nexusmods.com/phantombladezero/mods/239)。UE4SS 由 [UE4SS-RE 与贡献者](https://github.com/UE4SS-RE/RE-UE4SS)开发；游戏专用 1195 包由 [KintaroModding](https://github.com/KintaroModding/ue4ss/releases/tag/v3.0.1-1195-g1ceefac8)发布。本仓库不包含加载器，请从发布方页面获取。游戏与其素材属于各自权利人，本仓库不含游戏文件。

