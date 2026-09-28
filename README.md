# 小镇家园 · iOS 版

Godot 4.7 做的中世纪城镇经营游戏，这里是它的 iOS 打包工程。

## 目录说明

- `project.godot` / `main.tscn` / `scripts/`：游戏本体（Godot 工程）
- `assets.zip`：游戏素材（8,672 个文件，解压后是 `assets/`）
- `export_presets.cfg`：iOS 导出预设
- `.github/workflows/build-ios.yml`：在 GitHub 的 macOS 机器上自动导出并编译成 IPA

## 怎么出包

推送代码到 `main`，或者手动运行 `build-ios` 工作流，跑完在 Artifacts 里下载
`xiaozhen-ios-ipa`，解压得到 `xiaozhen-ios-unsigned.ipa`，用 TrollStore 安装即可。

## 本地（有 Mac 的话）

```bash
unzip assets.zip                      # 先解压素材
# 安装 Godot 4.7.2 与对应导出模板后：
godot --headless --path . --import
godot --headless --path . --export-release "iOS" build/ios/game.ipa
# 生成的 Xcode 工程用 Xcode 打开，关闭签名后 Archive / 或者直接 xcodebuild
```
