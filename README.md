# PhantomBladeZero-PointingDown-Mod-mod 影之刃零下指动作mod
The downward-pointing gesture animation from the Souls series has been ported to Phantom Blade Zero.将魂系列下指动作移植进了影之刃零中
# Version: 0.5.4
# 版本：0.5.4

Ports the original point-down taunt animation from *Elden Ring* into *Phantom Blade Zero*.
将《艾尔登法环》原版下指嘲讽动作移植到《影之刃零》。

Press **O** to play the animation, use **WASD** to smoothly rotate your character during the animation, move the camera with the mouse, and press **Backspace** to cancel the animation early.
按 **O** 播放，动作期间可用 **WASD** 平滑转向、鼠标转动镜头，按 **Backspace** 提前取消。

## Implementation
## 实现方式

The original animation has been retargeted to match the game's skeleton and converted into a native AnimSequence.
原版动作经过骨骼重定向，制作为匹配游戏骨架的原生 AnimSequence。

The animation is loaded through PAK, UTOC, and UCAS animation containers.
通过 PAK、UTOC、UCAS 动画容器加载动画。

The UE4SS Lua script handles key input, animation playback, input restrictions, and input restoration when the animation ends.
UE4SS Lua 脚本负责按键触发、动作播放、输入限制和结束恢复。

The animation is played using the character's existing model.
使用角色现有模型播放动画。

Movement, attacks, and dodging are disabled during the animation.
动作期间限制移动、攻击和闪避。

Camera orientation and sensitivity are automatically calibrated based on mouse input during normal gameplay.
镜头方向与灵敏度根据正常游玩时的鼠标输入自动校准。

## Licensing
## 许可情况

This is an unofficial mod, and no specific authorization has been obtained from the rights holders of either game.
本项目为非官方 MOD，未取得两款游戏权利人的专项授权。

The rights to the game titles, characters, and animation assets belong to their respective rights holders.
游戏名称、角色及动画素材的权利归各自权利人所有。

UE4SS and related components included in this package are distributed under the MIT License. See [UE4SS License File](第三方许可/UE4SS_LICENSE.txt).
随包 UE4SS 及相关组件使用 MIT 许可证，详见 [UE4SS 许可文件](第三方许可/UE4SS_LICENSE.txt)。

This license applies only to the corresponding third-party code and does not cover game animation assets.
该许可证适用于对应第三方代码，不涵盖游戏动画素材。

No separate open-source license has been specified for the original scripts developed for this project.
本项目自编脚本尚未另行指定开源许可证。

## Compatibility
## 兼容情况

**Verified:** Windows 64-bit Steam version of *Phantom Blade Zero*, Build **26266538**, running on a customized version of Unreal Engine **5.7.4**.
**已验证：** Windows 64 位 Steam 版《影之刃零》，Build **26266538**，游戏使用定制 UE **5.7.4**。

**Verified loader:** UE4SS **3.0.1 Beta #0**, commit **1ceefac8**, included in the initial release package.
**已验证加载器：** UE4SS **3.0.1 Beta #0**，提交号 **1ceefac8**，首次安装包内已提供。

**Tested:** Normal animation playback, different character skins, smooth turning, and mouse camera control.
**已实测：** 动作正常播放、不同人物皮肤、平滑转向及鼠标镜头控制。

Other game versions, other UE4SS versions, gamepad right-stick camera control, and compatibility with other mods have not yet been tested.
其他游戏版本、其他 UE4SS 版本、手柄右摇杆镜头及与其他 MOD 共存的情况尚未验证。

Mods that modify the same key bindings, character animations, or input logic may cause conflicts.
修改相同按键、角色动画或输入逻辑的 MOD 可能发生冲突。

Please refer to the included *Phantom Blade Zero Point-Down Gesture Mod Quick Guide* for installation and uninstallation instructions.
安装与卸载请阅读随包的《影之刃零下指动作MOD简明教程》。
