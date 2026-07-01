# Basic Tutorial 16: Platform-specific Elements 教程讲解

本文讲解 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/platform-specific-elements.html?gi-language=c>

这一篇没有 C 源码 demo，主题是 **平台相关 element**。GStreamer 是跨平台框架，但并不是所有 element 都能在所有平台上使用。尤其是视频显示、音频输出、摄像头采集、硬件解码这些能力，往往和操作系统、窗口系统、音频系统、GPU API 强相关。

通常情况下，如果使用：

```text
playbin
autovideosink
autoaudiosink
```

你不需要关心具体平台该选哪个 sink。GStreamer 会尽量自动选择合适的 element。

但如果你要手动搭 pipeline，或者要嵌入窗口、使用硬件加速、指定音频后端、接入移动端系统媒体库，就需要了解这些平台相关 element。

## 这篇教程解决什么问题

它回答的是：

- Linux 上视频显示该用什么 sink？
- Windows 上推荐哪个视频 sink？
- macOS/iOS/Android 上有哪些可用 sink？
- 哪些 element 已经过时或不推荐？
- 什么时候应该使用平台专用 element，什么时候交给 `auto*` element？

核心原则是：

```text
能用 playbin/autovideosink/autoaudiosink 时，优先交给自动选择。
需要平台特性或精确控制时，再手动选平台相关 element。
```

## Cross Platform

### glimagesink

`glimagesink` 是跨平台视频 sink，基于 OpenGL 或 OpenGL ES。

它的特点：

- 支持视频缩放。
- 支持缩放过滤，减轻锯齿。
- 实现了 `VideoOverlay` 接口，可以嵌入到应用自己的窗口中。
- 在多数平台上是推荐的视频 sink。
- 在 Android 和 iOS 上，它是唯一可用的视频 sink。

例子：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! glimagesink
```

如果输入已经是 OpenGL 纹理或希望走 GPU 路径，可以考虑 GL 相关链路。

官方教程提到，它可以拆成：

```text
glupload ! glcolorconvert ! glimagesinkelement
```

这样可以在中间插入更多 OpenGL 硬件加速处理。

适合场景：

- 跨平台视频显示。
- 希望利用 GPU。
- 需要把视频嵌入 GUI 窗口。
- Android / iOS 视频输出。

注意：Windows 上官方更推荐 `d3d11videosink`。

## Linux

Linux 上视频 sink 和窗口系统关系很密切。传统桌面环境中常见的是 X11；现代系统也可能使用 Wayland。官方教程这里重点列了 X11 相关 sink 和 ALSA/PulseAudio 音频 sink。

### ximagesink

`ximagesink` 是基于 X Window System 的标准 RGB 视频 sink。

特点：

- 只支持 RGB。
- 实现了 `VideoOverlay`，可以嵌入其他窗口。
- 不支持内部缩放。
- 不支持 RGB 之外的颜色格式。

如果需要缩放或格式转换，需要在前面加：

```text
videoconvert
videoscale
```

例子：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! videoscale ! ximagesink
```

适合场景：

- X11 环境。
- 简单 RGB 视频显示。
- 需要嵌入窗口，但不追求 GPU 加速。

### xvimagesink

`xvimagesink` 基于 X Video Extension，也就是 Xv。

特点：

- 使用 Xv 扩展。
- 可以用 GPU 高效缩放。
- 实现了 `VideoOverlay`。
- 只有硬件和驱动支持 Xv 时才可用。

例子：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! xvimagesink
```

相比 `ximagesink`，`xvimagesink` 更适合需要缩放的视频显示。但在现代系统上，也可以优先考虑 `glimagesink` 或自动 sink。

### alsasink

`alsasink` 通过 ALSA 输出到声卡。

ALSA 是 Linux 的底层音频系统，几乎所有 Linux 平台都有。

例子：

```sh
gst-launch-1.0 audiotestsrc ! audioconvert ! audioresample ! alsasink
```

特点：

- 低层接口，靠近声卡。
- 可用范围广。
- 配置可能比较复杂。
- 在桌面应用里不一定是最方便的选择。

适合场景：

- 嵌入式 Linux。
- 需要直接控制 ALSA 设备。
- 没有 PulseAudio/PipeWire 等高层音频服务。

### pulsesink

`pulsesink` 把音频输出到 PulseAudio server。

例子：

```sh
gst-launch-1.0 audiotestsrc ! audioconvert ! audioresample ! pulsesink
```

特点：

- 比 ALSA 更高层。
- 更容易使用。
- 支持更多桌面功能，例如混音、设备切换、音量管理。
- 老旧 Linux 发行版上曾经可能不稳定。

适合场景：

- 桌面 Linux。
- 用户会切换音频设备。
- 需要接入系统音频服务。

补充：很多现代 Linux 桌面使用 PipeWire，但兼容 PulseAudio API，因此 `pulsesink` 在这些系统上仍可能工作。

## macOS

官方教程标题仍写作 Mac OS X，但实际可以理解为 macOS。

### osxvideosink

`osxvideosink` 是 macOS 上的视频 sink。

例子：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! osxvideosink
```

同时，macOS 上也可以使用 `glimagesink` 通过 OpenGL 绘制。

一般建议：

- 简单显示可以依赖 `autovideosink`。
- 需要跨平台 OpenGL 路径时考虑 `glimagesink`。
- 需要 macOS 特定行为时再指定 `osxvideosink`。

### osxaudiosink

`osxaudiosink` 是 macOS 上的音频 sink。

例子：

```sh
gst-launch-1.0 audiotestsrc ! audioconvert ! audioresample ! osxaudiosink
```

如果使用 `autoaudiosink` 或 `playbin`，GStreamer 通常会自动选择它。

## Windows

Windows 上视频输出和 Direct3D、DirectShow、WASAPI、DirectSound 等系统 API 相关。

### d3d11videosink

`d3d11videosink` 基于 Direct3D 11，是 Windows 上推荐的视频 sink。

特点：

- 官方推荐用于 Windows。
- 支持 `VideoOverlay`。
- 支持缩放和颜色空间转换。
- 支持 zero-copy 路径，性能和功能都较好。

例子：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! d3d11videosink
```

适合场景：

- Windows 8 及更新系统。
- 希望使用现代 Windows 图形栈。
- 追求性能和功能完整性。

### d3dvideosink

`d3dvideosink` 基于 Direct3D 9。

特点：

- 支持缩放和过滤。
- 实现 `VideoOverlay`。
- 可以嵌入应用窗口。
- 不推荐用于 Windows 8 或更新目标平台。

例子：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! d3dvideosink
```

现在更推荐优先考虑 `d3d11videosink`。

### dshowvideosink deprecated

`dshowvideosink` 基于 DirectShow。

它可以使用不同渲染后端，例如 EVR、VMR9、VMR7，也支持缩放和窗口嵌入。

但官方教程明确标注为 deprecated，并且说大多数情况下不推荐使用。

除非维护旧项目或有明确兼容性需求，新项目不要优先选它。

### wasapisink / wasapi2sink

`wasapisink` 和 `wasapi2sink` 基于 WASAPI，是 Windows 上默认音频 sink。

特点：

- WASAPI 从 Windows Vista 开始可用。
- `wasapi2sink` 是 `wasapisink` 的替代者。
- Windows 8 或更新系统默认使用 `wasapi2sink`。
- 更旧系统可能使用 `wasapisink`。

例子：

```sh
gst-launch-1.0 audiotestsrc ! audioconvert ! audioresample ! wasapi2sink
```

实际开发中，如果不需要强制指定，可以直接使用：

```text
autoaudiosink
```

### directsoundsink deprecated

`directsoundsink` 基于 DirectSound，DirectSound 在所有 Windows 版本中都可用。

但它已经不再是现代 Windows 音频输出的首选。新项目更应该使用 WASAPI 相关 sink，或者交给 `autoaudiosink`。

### dshowdecwrapper

`dshowdecwrapper` 可以包装系统中的 DirectShow decoder，让 GStreamer pipeline 使用这些 DirectShow 解码器。

官方教程提醒：DirectShow 和 GStreamer 都是多媒体框架，但它们的 pipeline 不能直接互连。`dshowdecwrapper` 的作用是把 DirectShow 解码器包装成 GStreamer element。

可以用：

```sh
gst-inspect-1.0 dshowdecwrapper
```

或者查看系统里可用的 wrapped decoders。

适合场景：

- Windows 上需要利用系统已有 DirectShow 解码器。
- 某些格式没有 GStreamer 原生 decoder，但系统 DirectShow decoder 可用。

不过新项目应优先考虑 GStreamer 原生插件和现代硬件解码路径。

## Android

Android 上很多能力来自系统多媒体 API 和移动 GPU。官方教程列出的 element 都很平台专用。

### openslessink

`openslessink` 是 Android 上唯一可用的音频 sink，基于 OpenSL ES。

例子概念上类似：

```sh
gst-launch-1.0 audiotestsrc ! audioconvert ! audioresample ! openslessink
```

在实际 Android 应用中，通常不会直接在 shell 里这样运行，而是通过 Android 集成代码构建 pipeline。

### openslessrc

`openslessrc` 是 Android 上唯一可用的音频 source，同样基于 OpenSL ES。

它用于从 Android 设备麦克风采集音频。

例子概念上：

```sh
gst-launch-1.0 openslessrc ! audioconvert ! audioresample ! fakesink
```

### androidmedia

`androidmedia` 插件让 GStreamer 使用 Android 的 `android.media.MediaCodec` API。

特点：

- 可以访问设备上的音视频 codec。
- 包括硬件 codec。
- Android API level 16，也就是 Jelly Bean 起可用。
- 硬件 decoder 连接到 `glimagesink` 时，可以形成高性能 zero-copy 解码显示路径。

适合场景：

- Android 上使用硬件解码。
- 高性能视频播放。
- 移动端低功耗播放。

### ahcsrc

`ahcsrc` 是 Android 摄像头 source。

特点：

- 从 Android 设备摄像头采集视频。
- 属于 `androidmedia` 插件。
- 使用 Android `android.hardware.Camera` API。

适合场景：

- Android 摄像头采集。
- 实时预览、录制、推流。

例子概念上：

```sh
gst-launch-1.0 ahcsrc ! videoconvert ! glimagesink
```

具体可用性和权限、Android 版本、应用集成方式相关。

## iOS

iOS 上的 element 更偏向系统媒体库和硬件能力。

### osxaudiosink

`osxaudiosink` 也是 iOS 上可用的音频 sink。

如果使用 `autoaudiosink`，GStreamer 通常会自动选择合适的 iOS 音频输出。

### iosassetsrc

`iosassetsrc` 用来读取 iOS assets，也就是 Library 中的文档，例如照片、音乐、视频。

`playbin` 在遇到：

```text
assets-library://
```

scheme 的 URI 时，可以自动实例化它。

适合场景：

- 从 iOS 照片库或媒体库读取资源。
- 处理 `assets-library://` URI。

### iosavassetsrc

`iosavassetsrc` 用来读取并解码 iOS audiovisual assets。

`playbin` 在遇到：

```text
ipod-library://
```

scheme 的 URI 时，可以自动实例化它。

特点：

- 读取 iOS Library 中的音视频资源。
- 解码由系统完成。
- 如果有专用硬件，系统会使用硬件解码。

适合场景：

- 读取 iPod/music library 资源。
- 希望使用系统解码能力。

## VideoOverlay 是什么

教程里很多视频 sink 都提到实现了 `VideoOverlay` 接口。

简单说，`VideoOverlay` 允许应用把 GStreamer 视频输出嵌入到自己创建的窗口中，而不是让 sink 自己弹出独立窗口。

典型场景：

- GTK/Qt/Win32/Cocoa 应用里嵌入视频区域。
- 播放器 UI 中固定一个视频控件。
- 多个视频窗口或多画面显示。

前面的 Basic Tutorial 5 是 GTK 集成 demo。它通过 GTK video sink 获取 widget，把视频嵌入 GTK 界面；这和 `VideoOverlay` 解决的问题很接近。

## auto sink 和平台 sink 怎么选

### 优先使用自动选择

如果你只是想播放：

```sh
gst-launch-1.0 playbin uri=file:///home/user/video.mp4
```

或者：

```sh
gst-launch-1.0 videotestsrc ! autovideosink
gst-launch-1.0 audiotestsrc ! autoaudiosink
```

通常就够了。

自动选择的好处：

- 跨平台。
- 不需要关心插件是否安装。
- 系统升级或插件变化后仍可能自动选择更合适的后端。

### 需要明确平台行为时手动指定

手动指定平台 sink 的场景：

- Windows 上想强制用 `d3d11videosink`。
- Linux 嵌入式上想强制用 `alsasink`。
- Android 上要使用 `glimagesink` 或硬件 decoder。
- 应用需要嵌入窗口，并确认某个 sink 的 overlay 行为。
- 排查 `autovideosink` 选择了不合适的 sink。

例如：

```sh
gst-launch-1.0 playbin uri=file:///home/user/video.mp4 video-sink=d3d11videosink
```

或者手写管线：

```sh
gst-launch-1.0 filesrc location=test.webm ! decodebin ! videoconvert ! glimagesink
```

## 如何查看本机可用 Element

平台相关 element 不一定安装。用：

```sh
gst-inspect-1.0 glimagesink
gst-inspect-1.0 d3d11videosink
gst-inspect-1.0 ximagesink
gst-inspect-1.0 pulsesink
gst-inspect-1.0 wasapi2sink
```

如果找不到，说明当前平台或插件安装中不可用。

也可以列出相关插件：

```sh
gst-inspect-1.0 | grep sink
gst-inspect-1.0 | grep src
```

排查自动选择时，可以打开日志：

```sh
GST_DEBUG=2,autodetect*:5 gst-launch-1.0 videotestsrc ! autovideosink
```

观察 `autovideosink` 最终选择了哪个实际 sink。

## 和前面教程的关系

| 概念 | 关联教程 |
| --- | --- |
| `playbin` 自动选择 sink | Basic Tutorial 1、4、5、12、13 |
| GTK/工具包嵌入视频 | Basic Tutorial 5 |
| `gst-inspect-1.0` 查看 element | Basic Tutorial 10 |
| debug 日志排查自动选择 | Basic Tutorial 11 |
| handy elements 中的 `autovideosink/autoaudiosink` 思路 | Basic Tutorial 14 |

这篇教程相当于给前面教程里的 `auto*` element 补充背景：自动选择背后实际会落到某个具体平台 sink 上。

## 关键 Element 总结

| 平台 | Element | 类型 | 说明 |
| --- | --- | --- | --- |
| Cross-platform | `glimagesink` | video sink | OpenGL/OpenGL ES，除 Windows 外多数平台推荐，Android/iOS 唯一视频 sink |
| Linux | `ximagesink` | video sink | X11 RGB sink，不支持内部缩放 |
| Linux | `xvimagesink` | video sink | Xv sink，支持 GPU 缩放，需要硬件/驱动支持 |
| Linux | `alsasink` | audio sink | ALSA 低层音频输出 |
| Linux | `pulsesink` | audio sink | PulseAudio 高层音频输出 |
| macOS | `osxvideosink` | video sink | macOS 视频输出 |
| macOS | `osxaudiosink` | audio sink | macOS 音频输出 |
| Windows | `d3d11videosink` | video sink | Direct3D 11，Windows 推荐 |
| Windows | `d3dvideosink` | video sink | Direct3D 9，新系统不推荐 |
| Windows | `dshowvideosink` | video sink | DirectShow，deprecated |
| Windows | `wasapisink` | audio sink | WASAPI 音频输出 |
| Windows | `wasapi2sink` | audio sink | WASAPI 新实现，Windows 8+ 默认 |
| Windows | `directsoundsink` | audio sink | DirectSound，deprecated |
| Windows | `dshowdecwrapper` | decoder wrapper | 包装 DirectShow 解码器 |
| Android | `openslessink` | audio sink | Android OpenSL ES 音频输出 |
| Android | `openslessrc` | audio source | Android OpenSL ES 音频输入 |
| Android | `androidmedia` | codec plugin | 使用 Android MediaCodec，包括硬件 codec |
| Android | `ahcsrc` | video source | Android 摄像头输入 |
| iOS | `osxaudiosink` | audio sink | iOS 音频输出 |
| iOS | `iosassetsrc` | source | 读取 `assets-library://` 资源 |
| iOS | `iosavassetsrc` | source/decoder | 读取并解码 `ipod-library://` 资源 |

## 这篇教程的核心思想

GStreamer 的核心 API 是跨平台的，但音视频输入输出很难完全平台无关。窗口系统、音频服务、硬件解码 API、移动端媒体库都会影响 element 选择。

实际开发时：

- 普通播放优先用 `playbin`、`autovideosink`、`autoaudiosink`。
- 需要性能、嵌入窗口、硬件解码或系统媒体库时，再选平台专用 element。
- 用 `gst-inspect-1.0` 确认 element 是否存在、属性和 pad caps。
- 用 `GST_DEBUG` 查看自动 sink 最终选择了什么。

知道这些平台 element 的名字和定位，就能在跨平台项目里更快定位“为什么这条 pipeline 在我的机器能跑、在另一台机器不行”。

