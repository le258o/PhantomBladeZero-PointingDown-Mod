# PS 原生手柄支持

在关闭 Steam Input、使用游戏原生手柄输入时，支持触摸板手势及动作期间的双摇杆操作。

## 安装及操作

按原教程选择“首次安装”或“已有UE4SS”安装。`main.lua` 与 `PSNative.dll` 必须放在同一个 `PointDown/Scripts` 目录。升级前退出游戏并备份原脚本。

| 输入 | 功能 |
| --- | --- |
| 触摸板单指下滑 | 播放下指动作 |
| 触摸板单指上滑 | 取消动作 |
| 动作期间左摇杆 | 平滑调整角色朝向 |
| 动作期间右摇杆 | 控制镜头 |
| O / Backspace | 保留键盘播放 / 取消 |

站稳并等待当前攻击、闪避等动作结束再触发。触摸板无需按下；沿垂直方向滑动约四分之一高度以上，用时约 0.06—0.9 秒。每次手指接触只触发一次，手势之间至少间隔 1 秒。两指触摸不触发。

无需先使用鼠标校准。动作期间仍限制移动、攻击和闪避，取消或结束后恢复。

## 配置

`main.lua` 顶部提供以下参数：

- `PAD_DEADZONE=.18`：摇杆死区，应为 0（含）至 1（不含）。
- `PAD_YAW_SPEED=180`、`PAD_PITCH_SPEED=120`：动作期间镜头速度，单位为度/秒。
- `PAD_INVERT_Y=false`：设为 `true` 可反转垂直镜头。

镜头参数独立于游戏设置，不会自动同步原生镜头灵敏度或反转选项。鼠标未校准时使用保底参数，正常游玩中可继续自动校准。

## 实现

`PSNative.dll` 使用 `package.loadlib` 加载到游戏进程，无额外程序、窗口、托盘或驱动。使用共享只读 HID 句柄，不重新注册游戏的 Raw Input，不发送模拟键盘输入，也不发送 HID 输出或特征报文来改变设备模式。

DLL 入口不访问 Lua C API，返回零个 Lua 值，因此不链接 Lua 或 UE4SS SDK。手势通过脚本同目录的 `PSNative.event` 小文件传给 Lua；状态变化时原子替换该文件，Lua 约每 30ms 读取一次。目录需要可写。DLL 仅在宿主游戏进程位于前台时接受手势，过期或后台待处理手势会丢弃。

支持运行时拔插，最多读取 8 个兼容设备；触摸按设备独立跟踪。DLL 在进程生命周期内保持加载，避免脚本热重载后读取线程执行已卸载代码。更新或移除 DLL 前必须退出游戏。

## 测试与兼容性

- 用户实测：**DualSense、USB、Steam Input 关闭**，确认可以播放，基本使用正常；不将该反馈视为所有边界情况已逐项验证。
- 实测沿用的加载器：**UE4SS v4.0.0 PreRelease #1，ac877679**。仓库原包的 UE4SS 3.0.1 Beta #0 尚未对新增功能重新实测，需进一步确认。
- 原生离线测试：60 项断言，覆盖四个 PID 的 USB/完整蓝牙报文布局、短包拒绝、方向、单次触发、斜滑/双指/失焦/超时拒绝。
- 模拟引擎 Lua 测试：52 项断言，覆盖无需鼠标启动、摇杆、死区、键鼠保留、手势去重、取消、暂停及自然结束恢复。
- 实际 DLL 加载测试：通过 Lua 5.4.8 的 `package.loadlib` 调用入口并初始化。

解析白名单：Sony DualSense（0CE6）、DualSense Edge（0DF2）、DualShock 4（05C4/09CC），VID 均为 054C。除 DualSense USB 外尚无对应硬件实测。蓝牙仅处理设备/游戏已经提供的完整触摸报文；简化报文不会被误当作触摸数据。

第三方兼容手柄、Sony 无线接收器、隐藏 HID 或独占设备访问环境不在本次支持范围内。Xbox 触发绑定尚未加入。

## 构建和验证

需要 Windows x64 MinGW GCC；运行 Lua 测试还需要 Lua 5.4。无需在游戏机器上安装这些开发工具。

```powershell
./source/PSNative/build.ps1 -Compiler gcc -Lua lua -RunTests
```

脚本在仓库根目录的 `work/` 编译并测试，将 DLL 复制到两套安装目录。编译参数为 `-std=c99 -Wall -Wextra -Werror -O2 -shared -static-libgcc`，链接系统 HID 和 SetupAPI 库。发布重编译的 DLL 后应刷新根目录校验表中的对应 SHA256。

报文结构核对来源：[SDL PS5 驱动](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_ps5.c)、[SDL PS4 驱动](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_ps4.c)。本模块没有链接或复制 SDL 代码。

## 排查及回退

下滑无反应时先尝试 O，区分手势识别与动画播放问题。UE4SS 日志中应出现 `PS native module loaded in-process`。`PSNative.event` 的序号及 `down` / `up` 可辅助确认触摸手势是否被接收。

没有事件文件时检查 DLL 加载、脚本路径和目录写入权限；已有事件但不播放时查看是否尚未站稳、当前动作未结束或资产加载失败。若原生手柄在正常游戏中可用、在本动作中摇杆无效，需核对游戏版本暴露的手柄轴名称。

回退时退出游戏，恢复备份的 `main.lua`，移除 `PSNative.dll`、`PSNative.event` 及可能残留的 `PSNative.event.tmp`。
