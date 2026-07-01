# Basic Tutorial 10: GStreamer Tools 教程讲解

本文讲解 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/gstreamer-tools.html?gi-language=c>

这一篇没有 C 源码 demo。它介绍的是 GStreamer 自带的几个命令行工具：

- `gst-launch-1.0`：不用写 C 代码，直接从命令行搭建并运行 pipeline。
- `gst-inspect-1.0`：查看系统里有哪些 element、插件、pad template、caps 和属性。
- `gst-discoverer-1.0`：分析媒体文件或 URI 的内部结构、时长、codec、tags、是否可 seek。

这些工具在日常开发里非常重要。写代码前，可以先用它们验证管线是否可行；遇到 link 失败、caps 不匹配、缺插件、媒体无法播放时，也常靠它们定位问题。

## 工具在哪里

在 Linux 上，这些工具通常随发行版的 GStreamer 工具包安装。

常见包名：

```text
Debian / Ubuntu: gstreamer1.0-tools
Fedora 风格发行版: gstreamer1
```

因为系统里可能同时存在多个 GStreamer 大版本，工具名会带版本号。本教程基于 GStreamer 1.0，所以工具名是：

```text
gst-launch-1.0
gst-inspect-1.0
gst-discoverer-1.0
```

可以先检查工具是否可用：

```sh
gst-launch-1.0 --version
gst-inspect-1.0 --version
gst-discoverer-1.0 --version
```

如果命令不存在，需要安装对应的 GStreamer tools 包。

## gst-launch-1.0 是什么

`gst-launch-1.0` 接受一段文本形式的 pipeline 描述，创建对应的 GStreamer element，连接它们，然后把 pipeline 设置为 `PLAYING`。

它特别适合：

- 快速验证某条 pipeline 是否能跑。
- 测试 element 属性和 caps filter。
- 复现 bug。
- 在写 C 代码前先试出正确的管线结构。

但它主要是调试工具，不建议把正式应用建立在调用 `gst-launch-1.0` 命令之上。正式程序应该使用 GStreamer API；如果想在代码里复用字符串形式的 pipeline，可以看 `gst_parse_launch()`。

## gst-launch-1.0 基本语法

最简单的 pipeline 描述是 element 之间用 `!` 连接：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! autovideosink
```

这条命令会创建：

```text
videotestsrc -> videoconvert -> autovideosink
```

含义：

- `videotestsrc` 生成测试视频图案。
- `videoconvert` 做视频格式转换，提高上下游兼容性。
- `autovideosink` 自动选择视频输出窗口。

`!` 表示把左边 element 的输出 pad 连接到右边 element 的输入 pad。若有多个可能 pad，GStreamer 会根据 pad caps 选择兼容的 pad。

停止运行可以在终端按：

```text
Ctrl+C
```

## 设置 Element 属性

element 属性可以写在 element 名后面：

```sh
gst-launch-1.0 videotestsrc pattern=11 ! videoconvert ! autovideosink
```

这里设置了 `videotestsrc` 的 `pattern` 属性。多个属性可以用空格继续追加：

```sh
gst-launch-1.0 audiotestsrc freq=440 volume=0.2 ! autoaudiosink
```

想知道某个 element 有哪些属性，用：

```sh
gst-inspect-1.0 videotestsrc
gst-inspect-1.0 audiotestsrc
```

## 命名 Element

复杂 pipeline 里，经常需要从后面引用前面已经创建的 element。这时可以给 element 命名：

```sh
gst-launch-1.0 videotestsrc ! videoconvert ! tee name=t \
  ! queue ! autovideosink \
  t. ! queue ! autovideosink
```

这里：

- `tee name=t` 创建一个 `tee`，名字叫 `t`。
- 第一条分支直接从 `tee` 往后连。
- 第二条分支用 `t.` 引用前面那个 `tee`，再连到另一个 `queue ! autovideosink`。

管线结构是：

```text
videotestsrc -> videoconvert -> tee
                                 -> queue -> autovideosink
                                 -> queue -> autovideosink
```

这里的 `queue` 很重要。第 7 篇教程已经讲过：`tee` 拆分多路后，每个分支通常要加 `queue`，让分支在独立线程中推进，避免互相阻塞。

## 指定 Pad

有些 element 有多个 pad，或者 pad 名称很重要。这时可以通过“element 名字 + 点 + pad 名”来指定 pad。

例如从 WebM 里只取视频流：

```sh
gst-launch-1.0 souphttpsrc location=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm \
  ! matroskademux name=d \
  d.video_0 ! matroskamux ! filesink location=sintel_video.mkv
```

这里：

- `matroskademux name=d` 把 WebM/Matroska 容器拆开。
- `d.video_0` 指定使用 demuxer 的视频输出 pad。
- `matroskamux` 把视频重新封装成 Matroska。
- `filesink` 写到 `sintel_video.mkv`。

只取音频流可以写成：

```sh
gst-launch-1.0 souphttpsrc location=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm \
  ! matroskademux name=d \
  d.audio_0 ! vorbisparse ! matroskamux ! filesink location=sintel_audio.mka
```

注意这里用了 `vorbisparse`。它会从 Vorbis 码流中提取必要信息放进 caps，让后面的 `matroskamux` 知道如何处理这路音频。

这两个例子没有解码，也没有播放；只是 demux 后重新 mux，相当于从容器里抽取某一路流再重新封装。

## Caps Filter

Caps filter 用来约束链路中允许通过的数据格式。

当 element 有多个输出 pad，或者下游 element 的 sink pad 是 `ANY`，GStreamer 自动选择 pad 时可能存在歧义。比如：

```sh
gst-launch-1.0 souphttpsrc location=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm \
  ! matroskademux ! filesink location=test
```

`filesink` 可以接受任何数据，`matroskademux` 又可能输出音频和视频。最后到底连到音频 pad 还是视频 pad，不够明确。

可以用 caps filter 消除歧义：

```sh
gst-launch-1.0 souphttpsrc location=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm \
  ! matroskademux ! video/x-vp8 ! matroskamux ! filesink location=sintel_video.mkv
```

其中：

```text
video/x-vp8
```

就是 caps filter。它像一个只允许特定 caps 通过的透明 element，告诉 GStreamer：“我只要 VP8 视频流。”

常见 caps filter 例子：

```sh
video/x-raw,width=320,height=200
audio/x-raw,rate=44100,channels=2
video/x-h264,profile=high
```

调试 caps 时常用：

```sh
gst-launch-1.0 -v ...
```

`-v` 会打印 pipeline 运行时协商出的 caps。

## gst-launch-1.0 常用例子

### 用 playbin 播放媒体

```sh
gst-launch-1.0 playbin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

这和 Basic Tutorial 1 的思路一样：使用 `playbin` 让 GStreamer 自动构造播放管线。

### 手写音视频播放管线

```sh
gst-launch-1.0 souphttpsrc location=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm \
  ! matroskademux name=d \
  ! queue ! vp8dec ! videoconvert ! autovideosink \
  d. ! queue ! vorbisdec ! audioconvert ! audioresample ! autoaudiosink
```

这条管线手动完成：

- HTTP 读取。
- Matroska/WebM demux。
- 视频 VP8 解码并显示。
- 音频 Vorbis 解码并播放。

它和 `playbin` 内部自动做的事情相似，但更显式。

### 转码为 MP4

```sh
gst-launch-1.0 uridecodebin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm name=d \
  ! queue ! videoconvert ! x264enc ! video/x-h264,profile=high ! mp4mux name=m ! filesink location=sintel.mp4 \
  d. ! queue max-size-time=5000000000 max-size-bytes=0 max-size-buffers=0 \
  ! audioconvert ! audioresample ! voaacenc ! m.
```

这条管线大致做：

```text
WebM -> decode -> H.264 video + AAC audio -> MP4
```

其中视频分支使用 `x264enc`，音频分支使用 `voaacenc`，最后用 `mp4mux` 封装成 MP4。

教程里特别提到：`x264enc` 默认可能会缓存多秒输入才输出数据，所以音频分支的 queue 增大了容量，避免管线 preroll 或启动时卡住。

### 缩放视频

```sh
gst-launch-1.0 uridecodebin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm \
  ! queue ! videoscale ! video/x-raw,width=320,height=200 ! videoconvert ! autovideosink
```

`videoscale` 负责缩放。真正指定输出尺寸的是 caps filter：

```text
video/x-raw,width=320,height=200
```

如果输入视频尺寸和 caps filter 要求不同，`videoscale` 就会执行缩放。

## gst-inspect-1.0 是什么

`gst-inspect-1.0` 用来查看 GStreamer 插件和 element 信息。

它有几种常用方式：

```sh
gst-inspect-1.0
```

不带参数时，列出系统里可用的插件和 element。

```sh
gst-inspect-1.0 vp8dec
```

带 element 名时，显示该 element 的详细信息。

```sh
gst-inspect-1.0 /path/to/plugin.so
```

带插件文件路径时，把该文件作为 GStreamer plugin 打开并显示其中的 element。

## gst-inspect-1.0 看什么

以：

```sh
gst-inspect-1.0 vp8dec
```

为例，最重要的几类信息是：

### Factory Details

显示 element 的基本信息：

```text
Long-name
Klass
Description
Author
```

这能帮助判断 element 的用途。

### Plugin Details

显示 element 来自哪个插件：

```text
Name
Description
Filename
Version
Source module
Binary package
```

当程序提示缺少插件时，这部分很有用。你可以看到某个 element 来自哪个插件包。

### Pad Templates

这是最重要的调试信息之一。

例如 `vp8dec`：

```text
SINK template: 'sink'
  Capabilities:
    video/x-vp8

SRC template: 'src'
  Capabilities:
    video/x-raw
```

这表示：

- `vp8dec` 的输入必须是 `video/x-vp8`。
- 它的输出是解码后的 `video/x-raw`。

当两个 element 不能 link 时，第一步通常就是用 `gst-inspect-1.0` 看它们的 pad template caps 是否有交集。

### Element Properties

这里列出 element 的属性、类型、默认值、取值范围和是否可读写。

例如：

```text
threads: Maximum number of decoding threads
post-processing: Enable post processing
```

这些属性可以在 `gst-launch-1.0` 中直接设置，也可以在 C 代码里用 `g_object_set()` 设置。

## gst-discoverer-1.0 是什么

`gst-discoverer-1.0` 是第 9 篇 `GstDiscoverer` 的命令行封装。

它接受一个 URI，分析媒体内部结构并打印信息：

```sh
gst-discoverer-1.0 https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm -v
```

它能显示：

- 容器类型。
- 音频、视频、字幕流。
- caps。
- codec。
- 语言。
- 采样率、声道数、分辨率、帧率。
- 时长。
- 是否可 seek。
- tags。

如果你不知道一个文件里到底是什么格式，先用 `gst-discoverer-1.0` 看一眼，通常就能决定后面 pipeline 该怎么搭。

## 三个工具怎么配合使用

实际开发时常见流程是：

1. 用 `gst-discoverer-1.0` 查看媒体文件结构。
2. 用 `gst-inspect-1.0` 查找需要的 demuxer、decoder、converter、sink。
3. 用 `gst-launch-1.0` 快速试出一条能跑的 pipeline。
4. 把验证过的结构翻译成 C 代码。

例如：

```sh
gst-discoverer-1.0 file:///home/user/test.webm -v
```

发现里面是 VP8 + Vorbis。

然后查 element：

```sh
gst-inspect-1.0 matroskademux
gst-inspect-1.0 vp8dec
gst-inspect-1.0 vorbisdec
```

再用 `gst-launch-1.0` 验证：

```sh
gst-launch-1.0 filesrc location=/home/user/test.webm \
  ! matroskademux name=d \
  ! queue ! vp8dec ! videoconvert ! autovideosink \
  d. ! queue ! vorbisdec ! audioconvert ! audioresample ! autoaudiosink
```

跑通以后，再把它改写成 `gst_element_factory_make()`、`gst_bin_add_many()`、`gst_element_link_many()`、动态 pad 回调等 C 代码。

## 和前面教程的对应关系

| 工具能力 | 对应教程 |
| --- | --- |
| `playbin uri=...` | Basic Tutorial 1、4、5 |
| `!` 链接 element | Basic Tutorial 2 |
| 动态 pad、demuxer 输出 pad | Basic Tutorial 3 |
| `-v` 查看协商 caps | Basic Tutorial 6 |
| `tee name=t`、`queue` 分支 | Basic Tutorial 7 |
| `appsrc` / `appsink` 不能完全靠 gst-launch 表达应用逻辑 | Basic Tutorial 8 |
| `gst-discoverer-1.0` | Basic Tutorial 9 |

这些工具不是和 C API 分开的另一套东西，而是同一套 GStreamer 概念的命令行入口。

## 常见调试套路

### 查看元素是否存在

```sh
gst-inspect-1.0 x264enc
```

如果没有输出或提示找不到，说明对应插件没安装。

### 查看某个 element 能接什么、能输出什么

```sh
gst-inspect-1.0 audioconvert
gst-inspect-1.0 videoconvert
gst-inspect-1.0 matroskademux
```

重点看 `Pad Templates` 和 `Capabilities`。

### 查看运行时 caps 协商

```sh
gst-launch-1.0 -v videotestsrc ! videoconvert ! autovideosink
```

`-v` 会打印 pad 上实际协商出的 caps。

### 检查媒体文件内部结构

```sh
gst-discoverer-1.0 file:///home/user/video.mp4 -v
```

看容器、音视频 codec、分辨率、帧率、采样率、是否可 seek。

### 先用 fakesink 验证前半段

```sh
gst-launch-1.0 filesrc location=test.webm ! matroskademux ! fakesink
```

`fakesink` 会接收数据但不显示、不播放。它适合用来验证某段 pipeline 是否能跑通。

## 关键命令总结

| 命令 | 作用 |
| --- | --- |
| `gst-launch-1.0 videotestsrc ! videoconvert ! autovideosink` | 运行测试视频管线 |
| `gst-launch-1.0 -v ...` | 运行管线并打印 caps 等详细信息 |
| `gst-launch-1.0 playbin uri=...` | 用 `playbin` 播放 URI |
| `gst-inspect-1.0` | 列出可用插件和 element |
| `gst-inspect-1.0 ELEMENT` | 查看某个 element 的 pad template、caps、属性 |
| `gst-discoverer-1.0 URI` | 探测媒体 URI |
| `gst-discoverer-1.0 URI -v` | 详细显示媒体拓扑、caps、tags |

## 这篇教程的核心思想

GStreamer 命令行工具是开发者的放大镜和试验台：

- `gst-launch-1.0` 用来快速搭管线、验证想法。
- `gst-inspect-1.0` 用来理解 element 能力、属性和 caps。
- `gst-discoverer-1.0` 用来分析媒体文件结构。

熟练使用这三个工具以后，写 C 代码会轻松很多。因为你可以先在命令行里把管线跑通，再把确定可行的结构翻译成程序。

