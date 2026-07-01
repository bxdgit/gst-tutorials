# Basic Tutorial 11: Debugging Tools 教程讲解

本文讲解 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/debugging-tools.html?gi-language=c>

这一篇没有 C demo，主题是 **调试工具**。前面的教程里，我们多数依赖 bus 上的 `ERROR` 消息来定位问题；但真实项目里，bus 错误经常只告诉你“出错了”，不一定告诉你为什么出错。GStreamer 内部和插件里埋了大量调试日志，这篇教程讲的就是如何把这些信息打开、过滤、保存，以及如何导出 pipeline 拓扑图。

主要内容有三块：

- 用 `GST_DEBUG` 打开 GStreamer 调试日志。
- 在自己的 C 代码里使用 GStreamer debug 宏输出日志。
- 用 DOT 文件导出 pipeline 图，观察 element 连接关系和 caps 协商。

## 为什么需要 Debugging Tools

GStreamer 是插件化框架，一个简单的 `playbin` 可能在内部创建很多 element；一个 `uridecodebin` 也可能根据媒体内容动态创建 demuxer、parser、decoder、converter。

所以很多问题只看应用层代码并不够：

- element 创建失败，不知道缺哪个插件。
- `gst_element_link()` 失败，不知道 caps 哪里不兼容。
- pipeline 进入不了 `PAUSED` 或 `PLAYING`。
- 网络 URI 能打开，但解码失败。
- `uridecodebin` 动态 pad 出现了，但不是预期格式。
- 音视频不同步、卡顿、queue 堵塞。
- `playbin` 内部到底创建了什么 element 不清楚。

这时就需要 GStreamer 的 debug log 和 pipeline graph。

## GST_DEBUG 是什么

`GST_DEBUG` 是一个环境变量，用来控制 GStreamer 的调试日志输出。

最简单的用法：

```sh
GST_DEBUG=2 gst-launch-1.0 filesrc location=non-existing-file.webm ! decodebin ! fakesink
```

`GST_DEBUG=2` 表示输出 debug level 小于等于 2 的信息。通常包括 `ERROR` 和 `WARNING`。

日志行大致长这样：

```text
0:00:00.868050000 1592 09F62420 WARN filesrc gstfilesrc.c:1044:gst_file_src_start:<filesrc0> error: No such file "non-existing-file.webm"
```

它包含时间戳、进程 ID、线程 ID、日志级别、调试类别、源码位置、函数名、对象名和具体消息。虽然一行很长，但信息密度很高。

## Debug Level

GStreamer 的日志等级是数字，数字越大，输出越多。

| Level | 名称 | 含义 |
| --- | --- | --- |
| 0 | none | 不输出调试信息 |
| 1 | ERROR | 致命错误，通常表示某个操作无法完成 |
| 2 | WARNING | 警告，非致命但可能导致可见问题 |
| 3 | FIXME | 已知不完整或需要修复的代码路径 |
| 4 | INFO | 信息性日志，通常是重要但不频繁的事件 |
| 5 | DEBUG | 常规调试信息，例如初始化、销毁、参数变化 |
| 6 | LOG | 更频繁的日志，例如 streaming 稳态过程 |
| 7 | TRACE | 非常频繁的追踪日志，例如引用计数变化 |
| 9 | MEMDUMP | 内存内容 dump，日志量最大 |

常用经验：

- `GST_DEBUG=2`：先看错误和警告，适合日常排错。
- `GST_DEBUG=3`：多看一些 FIXME，仍然比较可控。
- `GST_DEBUG=4`：信息量明显变大，适合进一步定位。
- `GST_DEBUG=5` 及以上：日志可能非常多，建议重定向到文件。

不要一上来就全局开到 `6`、`7` 或 `9`。日志会非常大，也可能因为终端疯狂输出让程序变慢。

## 按 Category 过滤日志

GStreamer 的 debug log 不只有 level，还有 category。每个插件或模块都会注册自己的 category，例如：

```text
filesrc
audiotestsrc
decodebin
GST_PADS
GST_CAPS
```

可以给不同 category 设置不同 level：

```sh
GST_DEBUG=2,audiotestsrc:6 gst-launch-1.0 audiotestsrc ! autoaudiosink
```

含义是：

- 默认 level 是 2。
- `audiotestsrc` category 使用 level 6。

也可以用通配符：

```sh
GST_DEBUG=2,audio*:6 gst-launch-1.0 audiotestsrc ! autoaudiosink
```

这表示所有以 `audio` 开头的 category 都使用 level 6。

下面两个写法等价：

```sh
GST_DEBUG=2
GST_DEBUG=*:2
```

`*` 表示所有 category。

## 查看所有 Debug Category

可以用：

```sh
gst-launch-1.0 --gst-debug-help
```

查看当前系统中已注册的 debug category。

注意：category 列表不是固定的。它取决于当前安装了哪些 GStreamer 插件；安装或删除插件后，列表会变化。

## 日志行怎么看

官方教程给了一个日志行例子：

```text
0:00:00.868050000 1592 09F62420 WARN filesrc gstfilesrc.c:1044:gst_file_src_start:<filesrc0> error: No such file "non-existing-file.webm"
```

可以拆成：

| 部分 | 含义 |
| --- | --- |
| `0:00:00.868050000` | 程序启动后的时间戳 |
| `1592` | 进程 ID |
| `09F62420` | 线程 ID |
| `WARN` | 日志级别 |
| `filesrc` | debug category |
| `gstfilesrc.c:1044` | GStreamer 源码文件和行号 |
| `gst_file_src_start` | 输出日志的函数 |
| `<filesrc0>` | 输出日志的对象名，可能是 element、pad 或其他对象 |
| `error: No such file ...` | 具体消息 |

对象名很有用。比如管线里有多个 `queue` 时，如果你手动命名成 `audio_queue`、`video_queue`，日志里就能直接看出是哪一路出了问题。

这也是为什么前面的 demo 经常给 element 起名字：

```c
gst_element_factory_make ("queue", "audio_queue");
gst_element_factory_make ("queue", "video_queue");
```

## 把日志保存到文件

日志很多时，建议重定向到文件：

```sh
GST_DEBUG=3 gst-launch-1.0 playbin uri=file:///home/user/test.mp4 2> gst.log
```

GStreamer debug log 默认通常输出到 stderr，所以用：

```text
2>
```

重定向 stderr。

如果想同时保存 stdout 和 stderr：

```sh
GST_DEBUG=3 gst-launch-1.0 playbin uri=file:///home/user/test.mp4 > gst.log 2>&1
```

随后可以搜索关键字：

```sh
grep -i error gst.log
grep -i warning gst.log
grep -i not-negotiated gst.log
grep -i missing gst.log
```

## 常用 GST_DEBUG 组合

### 只看错误和警告

```sh
GST_DEBUG=2 gst-launch-1.0 playbin uri=file:///home/user/test.mp4
```

这是最常用的第一步。

### 关注 caps 协商

```sh
GST_DEBUG=2,GST_CAPS:6 gst-launch-1.0 -v playbin uri=file:///home/user/test.mp4
```

适合排查：

- `not-negotiated`
- caps 不兼容
- pad link 失败
- format 不匹配

### 关注 pad 链接和事件

```sh
GST_DEBUG=2,GST_PADS:6 gst-launch-1.0 playbin uri=file:///home/user/test.mp4
```

适合排查动态 pad、request pad、pad probe、link/unlink 等问题。

### 关注 decodebin

```sh
GST_DEBUG=2,decodebin*:5,uridecodebin*:5 gst-launch-1.0 playbin uri=file:///home/user/test.mp4
```

适合排查自动解码时到底选择了什么 parser、decoder，以及动态 pad 是如何创建的。

### 关注 queue

```sh
GST_DEBUG=2,queue*:5 gst-launch-1.0 ...
```

适合排查多分支管线中的阻塞、缓冲和队列满/空问题。

这些 category 名称会随插件和版本变化。拿不准时，用 `--gst-debug-help` 查。

## 在 C 代码里输出 GStreamer Debug 日志

官方教程建议：如果你的代码在和 GStreamer 交互，最好也使用 GStreamer 的 debug 设施，而不是只用 `printf()` 或 `g_print()`。

常用宏：

```c
GST_ERROR ("Something failed: %s", reason);
GST_WARNING ("Unexpected value: %d", value);
GST_INFO ("Created element %s", name);
GST_DEBUG ("Current state is %s", state_name);
GST_LOG ("Processing buffer pts=%" GST_TIME_FORMAT, GST_TIME_ARGS (pts));
```

这些宏的参数形式和 `printf()` 类似。好处是：

- 应用自己的日志和 GStreamer 内部日志在同一套日志系统里。
- 日志带时间戳、线程 ID、category 等信息。
- 可以用 `GST_DEBUG` 统一控制输出级别。
- 更容易看出应用日志和 GStreamer 内部事件的先后关系。

## 自定义 Debug Category

如果直接使用 `GST_ERROR()`、`GST_DEBUG()` 等宏，默认 category 通常是 `default`。

为了让日志更清晰，可以定义自己的 category：

```c
GST_DEBUG_CATEGORY_STATIC (my_category);
#define GST_CAT_DEFAULT my_category
```

然后在 `gst_init()` 之后初始化：

```c
GST_DEBUG_CATEGORY_INIT (my_category, "my-app", 0,
    "Debug category for my application");
```

之后代码里的：

```c
GST_DEBUG ("Linking audio branch");
```

就会归到 `my-app` 这个 category 下。

运行时可以这样控制：

```sh
GST_DEBUG=2,my-app:5 ./my-player
```

这表示：

- GStreamer 其他 category 默认 level 2。
- 你的应用 category `my-app` 输出到 level 5。

## 导出 Pipeline 图

当 pipeline 变复杂时，只看代码或日志很难理解实际连接关系。尤其是：

- `playbin`
- `uridecodebin`
- `decodebin`
- 动态 pad
- tee 多分支
- 自动插入的内部 element

GStreamer 可以把 pipeline 导出成 GraphViz DOT 文件。

命令行方式：

```sh
mkdir -p /tmp/gst-dot
GST_DEBUG_DUMP_DOT_DIR=/tmp/gst-dot gst-launch-1.0 playbin uri=file:///home/user/test.mp4
```

设置 `GST_DEBUG_DUMP_DOT_DIR` 后，`gst-launch-1.0` 会在 pipeline 状态变化时生成 `.dot` 文件。文件名里通常包含状态信息，比如 `NULL_READY`、`READY_PAUSED`、`PAUSED_PLAYING` 等。

禁用这个功能，只要不设置这个环境变量即可。

## 把 DOT 转成图片

DOT 文件需要 GraphViz 渲染：

```sh
dot -Tpng /tmp/gst-dot/0.00.00.123456789-gst-launch.PAUSED_PLAYING.dot \
  -o pipeline.png
```

如果 SVG 更方便查看：

```sh
dot -Tsvg pipeline.dot -o pipeline.svg
```

生成图以后，可以看到：

- 实际创建了哪些 element。
- element 之间如何连接。
- 每条 link 上协商出的 caps。
- `playbin` 或 `uridecodebin` 内部到底展开成了什么结构。

这对理解复杂管线非常有帮助。

## 在 C 代码里导出 Pipeline 图

除了环境变量，应用代码里也可以主动导出图：

```c
GST_DEBUG_BIN_TO_DOT_FILE (GST_BIN (pipeline),
    GST_DEBUG_GRAPH_SHOW_ALL, "my-pipeline");
```

或者带时间戳：

```c
GST_DEBUG_BIN_TO_DOT_FILE_WITH_TS (GST_BIN (pipeline),
    GST_DEBUG_GRAPH_SHOW_ALL, "my-pipeline");
```

这些宏通常在你想观察某个关键时刻的 pipeline 状态时使用，例如：

- 刚创建完 pipeline。
- link 完所有 element。
- 进入 `PAUSED` 后。
- 收到动态 pad 后。
- 发生错误前后。

生成的 `.dot` 文件也会放到 `GST_DEBUG_DUMP_DOT_DIR` 指定的目录里。

## 推荐排错流程

### 1. 先用 gst-launch 复现

如果 C 程序里的 pipeline 有问题，先尽量把它翻译成一条 `gst-launch-1.0` 命令：

```sh
GST_DEBUG=2 gst-launch-1.0 ...
```

如果命令行也失败，说明问题大概率在管线结构、插件、caps 或数据源，而不是应用代码。

### 2. 打开基础日志

```sh
GST_DEBUG=2 ./your-app
```

先看 `ERROR` 和 `WARNING`。很多问题到这一步就够了。

### 3. 针对 category 加深日志

如果怀疑 caps：

```sh
GST_DEBUG=2,GST_CAPS:6 ./your-app
```

如果怀疑动态 pad：

```sh
GST_DEBUG=2,GST_PADS:6,decodebin*:5 ./your-app
```

如果怀疑网络源：

```sh
GST_DEBUG=2,soup*:5,urisourcebin*:5 ./your-app
```

### 4. 导出 DOT 图

```sh
mkdir -p /tmp/gst-dot
GST_DEBUG_DUMP_DOT_DIR=/tmp/gst-dot ./your-app
```

如果是 C 应用，必要时在关键位置加：

```c
GST_DEBUG_BIN_TO_DOT_FILE_WITH_TS (GST_BIN (pipeline),
    GST_DEBUG_GRAPH_SHOW_ALL, "before-error");
```

### 5. 保存日志再搜索

```sh
GST_DEBUG=3,GST_CAPS:6 ./your-app > gst.log 2>&1
```

常搜关键词：

```text
error
warning
not-negotiated
missing
could not link
no such element
not-linked
Internal data stream error
```

## 和前面教程的对应关系

| 场景 | 调试工具 |
| --- | --- |
| Basic Tutorial 3 动态 pad 没连上 | `GST_PADS:6`、DOT 图 |
| Basic Tutorial 4 seek 不生效 | `GST_EVENT:5`、`GST_SEEK:5`、基础 bus 错误 |
| Basic Tutorial 6 caps 看不懂 | `GST_CAPS:6`、`gst-launch-1.0 -v` |
| Basic Tutorial 7 tee/queue 多分支阻塞 | `queue*:5`、DOT 图 |
| Basic Tutorial 8 appsrc/appsink 无数据 | `appsrc*:5`、`appsink*:5`、基础 flow return |
| Basic Tutorial 9 discover 失败 | `GST_DEBUG=2`、缺插件信息 |
| Basic Tutorial 10 命令行管线失败 | `gst-inspect-1.0`、`GST_DEBUG=2` |

这些工具不是只给 GStreamer 内部开发者用的。日常写应用时，只要遇到不透明问题，就应该把它们拿出来。

## 关键命令总结

| 命令 / 环境变量 | 作用 |
| --- | --- |
| `GST_DEBUG=2 ./app` | 打开错误和警告日志 |
| `GST_DEBUG=2,category:5 ./app` | 默认 level 2，指定 category level 5 |
| `GST_DEBUG=2,audio*:6 ./app` | 用通配符匹配 category |
| `gst-launch-1.0 --gst-debug-help` | 查看已注册 debug category |
| `GST_DEBUG=3 ./app > gst.log 2>&1` | 保存日志到文件 |
| `GST_DEBUG_DUMP_DOT_DIR=/tmp/gst-dot ./app` | 导出 pipeline DOT 图 |
| `dot -Tpng pipeline.dot -o pipeline.png` | 把 DOT 渲染成 PNG |
| `GST_DEBUG_BIN_TO_DOT_FILE()` | C 代码中导出 pipeline 图 |
| `GST_DEBUG_BIN_TO_DOT_FILE_WITH_TS()` | C 代码中导出带时间戳的 pipeline 图 |

## 这篇教程的核心思想

GStreamer 很复杂，但它也提供了非常强的可观测性：

- `GST_DEBUG` 让你看到内部插件和 core 正在做什么。
- Debug category 让你只放大自己关心的部分，避免被日志淹没。
- `GST_ERROR()`、`GST_DEBUG()` 等宏让应用自己的日志和 GStreamer 日志合并到同一条时间线上。
- DOT 图让你把复杂 pipeline 可视化，尤其适合理解 `playbin`、`uridecodebin` 和动态 pad。

遇到问题时，不要只盯着 bus error。先用适当级别的日志和 pipeline 图把问题照亮，很多“玄学问题”都会变成具体的 caps、pad、插件或状态流转问题。

