# 瞬环 · SNAP LOOP

瞬环是一款竖屏单指生存游戏。按住屏幕，让攻击环扩张并锁定敌人，松手完成瞬斩。一斩命中三个敌人即可净斩，击碎环内红雷。观察敌人、红雷和外圈红线，在合适的时机松手。

经典模式包含五个阶段、五类主要敌人、分裂碎晶和穿场流火。互动训练从锁定一个晶核开始，逐步练习多杀、破雷和过载。首次训练可以跳过，也可以在设置中重玩。游戏支持离线游玩和简体中文、英文界面。设置和成绩保存在设备上。

## 在 iPhone 上运行

需要 iOS 26 或更新版本，以及支持 iOS 26 SDK 的 Xcode。打开 `SnapLoop.xcodeproj`，选择 `SnapLoop` scheme。在 **Signing & Capabilities** 选择自己的开发团队，根据需要修改 Bundle Identifier，再从 Xcode 运行到 iPhone 或模拟器。可以用 XcodeGen 根据 `project.yml` 重新生成工程。

```sh
swift test
xcodebuild -project SnapLoop.xcodeproj -scheme SnapLoop \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

## 规则与扩展

- `SnapLoop/Core/Rules.swift` 定义敌人运动、捕获条件和积分奖励。积分以 `10 × 击杀数²` 为基础，叠加破雷、贴脸、擦雷和满弓奖励。
- `SnapLoop/Core/WaveDirector.swift` 控制敌潮组合、间隔和阶段。推进依据是存活时间加上总击杀数乘以 `0.65`。
- `SnapLoop/Core/GameCore.swift` 在 120 Hz 模拟步中依次处理输入、过载、刷怪、红雷和敌人触核。同一步内，已经排队的松手先于过载和触核结算。
- `SnapLoop/Core/GameSession.swift` 管理触摸归属、暂停、恢复、命令队列和复现记录。Debug 构建把最近结束的经典对局保存为 App 容器中 `Library/Application Support/last-classic-run.json`。`Replay.reproduceRun()` 使用规则版本、种子和逐步命令重跑对局。
- `SnapLoop/App` 提供 SwiftUI、Liquid Glass、SpriteKit、触觉、合成声音和本地纪录。SpriteKit 的目标渲染频率为 60 FPS，粒子和震动有独立于玩法的随机源。

新增敌人时，为 `EnemyKind` 添加运动规则，在 `WaveDirector` 设置出场组合，并为 SpriteKit 和本地化添加对应形状与名称。新增奖励时，在 `ScoreRules` 中定义条件和分值，在 `ScoreBonus` 和纪录页面登记奖励类别。改变已有对局结果的规则更新应提升 `ArenaRules.version`。
