# Basic Tutorial 14: Handy Elements 教程讲解

本文讲解 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/handy-elements.html?gi-language=c>

这一篇没有 C 源码 demo，而是列出一批日常开发中非常值得熟悉的 GStreamer element。它们有的像 `playbin` 一样很“重”，内部能自动构造复杂管线；有的像 `identity`、`fakesink` 一样很“小”，但调试时特别有用。

官方教程中的例子主要使用 `gst-launch-1.0` 展示。你可以配合：

```sh
gst-launch-1.0 -v ...
```

查看运行时协商出的 pad caps。

## 这篇教程解决什么问题

GStreamer 的 element 非常多，新手很容易不知道该从哪里下手。这篇教程的价值在于提供一张“常用工具地图”：

- 想快速播放媒体：用 `playbin`。
- 想从 URI 解码成 raw audio/video：用 `uridecodebin`。
- 想读写本地文件：用 `filesrc`、`filesink`。
- 想测试管线是否正常：用 `videotestsrc`、`audiotestsrc`。
- 遇到 caps negotiation 问题：优先试 `videoconvert`、`audioconvert`、`videoscale`、`audioresample`。
- 想拆多路分支：用 `tee + queue`。
- 想限制格式：用 `capsfilter`。
- 想调试某段管线：用 `fakesink`、`identity`。

下面按官方教程的分类讲解。

## Bins

Bin 类型的 element 本身像一个普通 element，但内部会自动创建和管理其他 element。应用可以把它当成一个整体使用。

### playbin

`playbin` 是高级播放器 element。前面很多教程都用过它。

它负责完整播放流程：

```text
source -> demux -> decode -> convert -> audio/video sink
```

你只需要设置 URI：

```sh
gst-launch-1.0 playbin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

适合场景：

- 快速做播放器。
- 不想手动处理 demuxer、decoder、sink。
- 想让 GStreamer 自动选择合适插件。

局限：

- 内部结构比较复杂。
- 如果要精确控制每个 element，手写 pipeline 更合适。

### uridecodebin

`uridecodebin` 从 URI 读取数据，并自动解码到 raw media。

它会自动选择适合 URI scheme 的 source，例如 HTTP、本地文件等，然后连接到内部 decodebin。

例子：播放视频流：

```sh
gst-launch-1.0 uridecodebin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm ! videoconvert ! autovideosink
```

例子：播放音频流：

```sh
gst-launch-1.0 uridecodebin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm ! audioconvert ! autoaudiosink
```

注意：`uridecodebin` 像 demuxer 一样，可能根据媒体内容创建多个 source pad。例如一个视频文件可能有音频 pad 和视频 pad。这和 Basic Tutorial 3 的动态 pad 概念相关。

适合场景：

- 想自动读取并解码 URI。
- 但又想自己控制后面的 raw audio/video 处理链路。

### decodebin

`decodebin` 自动构造解码链路，直到输出 raw media。

它和 `uridecodebin` 的区别：

- `decodebin` 不负责创建 source。
- `uridecodebin` 会根据 URI 先创建 source，再内部使用类似 decodebin 的自动解码逻辑。

例子：

```sh
gst-launch-1.0 souphttpsrc location=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm ! decodebin ! autovideosink
```

适合场景：

- 你已经有 source，例如 `filesrc`、`souphttpsrc`。
- 希望 GStreamer 自动选择 demuxer、parser、decoder。

## File Input / Output

### filesrc

`filesrc` 从本地文件读取字节流。

例子：

```sh
gst-launch-1.0 filesrc location=/home/user/video.webm ! decodebin ! autovideosink
```

`filesrc` 输出 caps 通常是 `ANY`，因为它只是读文件字节，并不知道文件内部媒体类型。

如果需要识别文件类型，可以：

- 后接 `typefind`。
- 或者使用 `decodebin`，它内部会做 typefinding。
- 或者使用 Basic Tutorial 9 里的 `GstDiscoverer`。

### filesink

`filesink` 把收到的数据写入本地文件。

例子：生成 Ogg/Vorbis 文件：

```sh
gst-launch-1.0 audiotestsrc ! vorbisenc ! oggmux ! filesink location=test.ogg
```

注意：`filesink` 不会自动封装格式。你必须在它前面放合适的 encoder 和 muxer。比如：

```text
raw audio -> vorbisenc -> oggmux -> filesink
```

如果直接把 raw audio 写进 `.ogg` 文件，文件并不会自动变成合法 Ogg。

## Network

### souphttpsrc

`souphttpsrc` 通过 HTTP 从网络读取数据，底层使用 libsoup。

例子：

```sh
gst-launch-1.0 souphttpsrc location=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm ! decodebin ! autovideosink
```

适合场景：

- 直接从 HTTP/HTTPS URL 拉取媒体。
- 想手动搭建网络播放管线。

如果只是播放网络媒体，`playbin uri=https://...` 通常更简单；内部会自动选择类似 `souphttpsrc` 的 source。

## Test Media Generation

测试 source 很有用。它们产生“保证能工作”的测试数据，可以帮助你排除数据源本身的问题。

### videotestsrc

`videotestsrc` 生成测试视频图案。

例子：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! autovideosink
```

可以通过 `pattern` 属性改变图案：

```sh
gst-launch-1.0 videotestsrc pattern=smpte ! videoconvert ! autovideosink
```

适合场景：

- 测试视频 sink 是否工作。
- 测试视频转换、缩放、编码链路。
- 排除输入文件或摄像头的问题。

### audiotestsrc

`audiotestsrc` 生成测试音频信号。

例子：

```sh
gst-launch-1.0 audiotestsrc ! audioconvert ! autoaudiosink
```

可以设置频率：

```sh
gst-launch-1.0 audiotestsrc freq=440 ! audioconvert ! autoaudiosink
```

适合场景：

- 测试音频 sink 是否工作。
- 测试音频转换、重采样、编码链路。
- 做可视化测试，例如 Basic Tutorial 7 里的 `wavescope`。

## Video Adapters

Video adapter 用来解决视频格式、帧率、尺寸不匹配的问题。

### videoconvert

`videoconvert` 转换视频颜色空间和像素格式，例如：

- RGB 到 YUV。
- YUV 不同排列格式之间转换。
- RGBA、ARGB、BGRA 等 RGB 排列转换。

例子：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! autovideosink
```

这是解决视频 caps negotiation 问题的首选 element。官方教程给的经验是：当你不知道上下游能协商出什么格式时，插入 `videoconvert` 通常是安全的。

如果上下游本来就能直接理解彼此，`videoconvert` 会以 pass-through 方式工作，性能影响很小。

常见用法：

```text
decodebin ! videoconvert ! autovideosink
```

因为用户提供的文件格式不可控，而自动视频 sink 支持的格式也可能依赖平台。

### videorate

`videorate` 调整视频帧率。

它通过丢帧或复制帧，让输出匹配目标帧率。它不会做复杂插帧算法。

例子：把 30fps 转成 1fps：

```sh
gst-launch-1.0 videotestsrc ! video/x-raw,framerate=30/1 ! videorate ! video/x-raw,framerate=1/1 ! videoconvert ! autovideosink
```

适合场景：

- 下游要求固定帧率。
- 输入帧率未知或不稳定。
- 做缩略图、低帧率预览、帧率规整。

如果上下游已经能协商出共同帧率，`videorate` 也可以 pass-through。

### videoscale

`videoscale` 调整视频分辨率。

例子：

```sh
gst-launch-1.0 uridecodebin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm ! videoscale ! video/x-raw,width=178,height=100 ! videoconvert ! autovideosink
```

注意：真正要求输出尺寸的是 caps filter：

```text
video/x-raw,width=178,height=100
```

`videoscale` 根据这个 caps filter 执行缩放。

适合场景：

- 视频输出窗口尺寸由用户控制。
- 下游编码器或 sink 要求特定分辨率。
- 需要生成缩略图或低分辨率预览。

## Audio Adapters

Audio adapter 用来解决音频格式、采样率、时间戳连续性等问题。

### audioconvert

`audioconvert` 转换 raw audio 格式，例如：

- 整数和浮点格式转换。
- 位宽转换。
- signed / unsigned 转换。
- 大小端转换。
- 声道布局转换。

例子：

```sh
gst-launch-1.0 audiotestsrc ! audioconvert ! autoaudiosink
```

它是解决音频 caps negotiation 问题的首选 element。和 `videoconvert` 类似，当不需要转换时，它可以 pass-through。

常见用法：

```text
decodebin ! audioconvert ! audioresample ! autoaudiosink
```

### audioresample

`audioresample` 转换音频采样率。

例子：把音频重采样到 4000 Hz：

```sh
gst-launch-1.0 uridecodebin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm ! audioresample ! audio/x-raw,rate=4000 ! audioconvert ! autoaudiosink
```

注意：真正指定目标采样率的是 caps filter：

```text
audio/x-raw,rate=4000
```

`audioresample` 根据这个要求进行重采样。

适合场景：

- 音频设备只支持某些采样率。
- 编码器要求固定采样率。
- 做电话音质、低码率、语音处理等场景。

### audiorate

`audiorate` 用来修正音频时间戳，使输出音频流连续。

它通过插入或丢弃 samples 来补洞或消除重叠。它不是用来改变采样率的；改变采样率应该用 `audioresample`。

官方教程特别提醒：大多数时候，`audiorate` 不是你想要的那个 element。

适合场景：

- 输入音频时间戳不连续。
- 保存到某些要求 sample 连续的文件格式。
- 需要规整音频流时间轴。

日常播放和普通转码中，通常不需要主动加它。

## Multithreading

### queue

`queue` 做两件事：

1. 缓冲数据，直到达到某个限制。
2. 在 source pad 侧创建新线程，把上下游处理解耦。

当 queue 满了，上游继续 push 会阻塞，直到 queue 有空间。queue 也可以配置成满了就丢数据。

典型用途：

- `tee` 多分支后，每个分支前放一个 `queue`。
- 解耦耗时处理链路。
- 避免一个 sink 阻塞整个 pipeline。

例子可以参考 Basic Tutorial 7。

官方经验：如果不关心网络 buffering，优先用简单的 `queue`。

### queue2

`queue2` 不是 `queue` 的升级版，而是另一种实现。

它也能缓冲并创建线程边界，但额外支持把接收到的数据或部分数据存到磁盘文件，之后再读取。

它还会用更通用的 `BUFFERING` bus message 报告缓冲状态，这正是 Basic Tutorial 12 讲过的内容。

官方经验：如果关心网络 buffering，优先考虑 `queue2`。

在普通播放应用里，你经常不需要手动创建它，因为 `playbin` 内部可能已经使用了相关 buffering element。

### multiqueue

`multiqueue` 同时管理多路队列，适合音频、视频、字幕等多路流一起处理。

它的能力包括：

- 某一路暂时没数据时，允许其他队列适当增长。
- 某一路没连接时，可以丢弃数据而不是直接报错。
- 同步多路 stream，避免某一路走得太远。

它是高级 element，通常出现在 `decodebin` 内部。普通播放应用很少需要手动实例化。

### tee

`tee` 把一份输入流复制到多个输出分支。

例子：

```sh
gst-launch-1.0 audiotestsrc ! tee name=t ! queue ! audioconvert ! autoaudiosink t. ! queue ! wavescope ! videoconvert ! autovideosink
```

管线结构：

```text
audiotestsrc -> tee
                 -> queue -> audioconvert -> autoaudiosink
                 -> queue -> wavescope -> videoconvert -> autovideosink
```

关键点：`tee` 的每个分支都应该有独立 `queue`。否则一个分支堵住，其他分支也会被拖住。

这正是 Basic Tutorial 7 的主题。

## Capabilities

### capsfilter

`capsfilter` 限制数据格式，但不修改数据本身。

在 `gst-launch-1.0` 里写：

```sh
gst-launch-1.0 videotestsrc ! video/x-raw,format=GRAY8 ! videoconvert ! autovideosink
```

这中间的：

```text
video/x-raw,format=GRAY8
```

就是 caps filter。

如果在 C 代码里手动搭 pipeline，就要创建 `capsfilter` element，并设置它的 `caps` 属性。

适合场景：

- 指定视频尺寸、帧率、像素格式。
- 指定音频采样率、声道数、采样格式。
- 消除自动 pad 选择的歧义。
- 让 `videoscale`、`audioresample` 等 adapter 知道目标格式。

### typefind

`typefind` 用来识别媒体流类型。

它会运行 typefind functions，识别后设置 source pad caps，并发出 `have-type` 信号。

日常开发中，你通常不需要手动用它，因为：

- `decodebin` 内部会用。
- `GstDiscoverer` 能提供更丰富的媒体信息。

但如果你在做自定义 source、文件探测器或特殊输入流处理，`typefind` 很有用。

## Debugging

### fakesink

`fakesink` 是一个“吞掉数据”的 sink。它接收数据，但不显示、不播放、不写文件。

例子：

```sh
gst-launch-1.0 audiotestsrc num-buffers=1000 ! fakesink sync=false
```

适合场景：

- 排除真实 sink 的影响。
- 验证前半段 pipeline 是否能正常产出数据。
- benchmark 某段处理链路。
- 调试动态 pad、caps、decoder。

`sync=false` 表示不按时钟同步，尽可能快地消费数据，适合测试吞吐。

如果配合 `-v`，`fakesink` 可能输出很多信息。可以用 `silent` 属性控制噪声。

### identity

`identity` 是一个“原样通过”的 element。它不修改数据，但可以做很多诊断工作。

例子：随机丢弃 10% buffer：

```sh
gst-launch-1.0 audiotestsrc ! identity drop-probability=0.1 ! audioconvert ! autoaudiosink
```

适合场景：

- 在管线中插入一个观察点。
- 模拟丢包、丢帧。
- 检查 buffer offset、timestamp。
- 调试数据是否流到某个位置。

它看起来不起眼，但调试复杂 pipeline 时非常实用。

## 常用组合套路

### 测试视频输出是否正常

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! autovideosink
```

如果这条能跑，说明视频 sink 和基本显示链路没问题。

### 测试音频输出是否正常

```sh
gst-launch-1.0 audiotestsrc ! audioconvert ! audioresample ! autoaudiosink
```

如果这条能跑，说明音频输出链路没问题。

### 排查输入媒体问题

把真实 source 换成测试 source：

```sh
gst-launch-1.0 videotestsrc ! x264enc ! mp4mux ! filesink location=test.mp4
```

如果测试 source 能跑，而真实文件不行，问题可能在输入媒体、demux、decode 或 caps。

### 排查 sink 问题

把真实 sink 换成 `fakesink`：

```sh
gst-launch-1.0 filesrc location=test.webm ! decodebin ! fakesink
```

如果 `fakesink` 能跑，而 `autovideosink` 不行，问题可能在视频输出或显示环境。

### 排查 caps negotiation

在关键位置加 adapter：

```sh
gst-launch-1.0 uridecodebin uri=file:///home/user/test.mp4 ! videoconvert ! videoscale ! video/x-raw,width=640,height=360 ! autovideosink
```

或者音频：

```sh
gst-launch-1.0 uridecodebin uri=file:///home/user/test.mp4 ! audioconvert ! audioresample ! audio/x-raw,rate=48000 ! autoaudiosink
```

## 和前面教程的关系

| Element / 概念 | 关联教程 |
| --- | --- |
| `playbin` | Basic Tutorial 1、4、5、12、13 |
| `uridecodebin`、动态 pad | Basic Tutorial 3 |
| caps、capsfilter | Basic Tutorial 6、10 |
| `queue`、`tee` | Basic Tutorial 7 |
| `queue2`、buffering | Basic Tutorial 12 |
| `GstDiscoverer`、typefinding | Basic Tutorial 9 |
| `fakesink`、`identity` | Basic Tutorial 11 调试思路 |
| `videoconvert`、`audioconvert`、`audioresample` | 多数播放和转换 demo 都会用到 |

## 关键 Element 总结

| Element | 作用 | 常见用途 |
| --- | --- | --- |
| `playbin` | 完整播放器 bin | 快速播放 URI |
| `uridecodebin` | 从 URI 解码到 raw media | 自动 source + decode |
| `decodebin` | 自动 demux/parse/decode | 已有 source 时自动解码 |
| `filesrc` | 读本地文件 | 文件输入 |
| `filesink` | 写本地文件 | 文件输出 |
| `souphttpsrc` | HTTP/HTTPS 输入 | 网络 source |
| `videotestsrc` | 测试视频源 | 验证视频链路 |
| `audiotestsrc` | 测试音频源 | 验证音频链路 |
| `videoconvert` | 视频格式转换 | 解决视频 caps 问题 |
| `videorate` | 调整视频帧率 | 固定帧率输出 |
| `videoscale` | 调整视频尺寸 | 缩放、适配 sink/encoder |
| `audioconvert` | 音频格式转换 | 解决音频 caps 问题 |
| `audioresample` | 音频采样率转换 | 适配设备或编码器 |
| `audiorate` | 修正音频时间连续性 | 特殊时间戳修复 |
| `queue` | 缓冲并创建线程边界 | 多分支、解耦上下游 |
| `queue2` | 网络缓冲/可落盘队列 | streaming buffering |
| `multiqueue` | 多路流队列管理 | decodebin 内部、多流同步 |
| `tee` | 一路拆多路 | 同时播放、保存、分析 |
| `capsfilter` | 限制 caps | 指定格式、尺寸、采样率 |
| `typefind` | 识别媒体类型 | 自定义探测或 decodebin 内部 |
| `fakesink` | 吞掉数据 | 排除 sink、测试前半段 |
| `identity` | 原样通过并可诊断 | 插入观察点、模拟丢包 |

## 这篇教程的核心思想

GStreamer 开发并不是每次都从零搭复杂管线。熟悉这些 handy elements 后，你会更自然地组合它们：

- 用 bin 类 element 快速完成复杂任务。
- 用 test source 和 fake sink 缩小问题范围。
- 用 convert/resample/scale/rate 类 adapter 解决 caps negotiation。
- 用 queue/tee 构建多线程多分支管线。
- 用 capsfilter 精确约束格式。
- 用 identity 在复杂管线里插入观察点。

这些 element 是日常 GStreamer 调试和工程开发的“常备工具箱”。掌握它们，比死记某一条固定 pipeline 更重要。

