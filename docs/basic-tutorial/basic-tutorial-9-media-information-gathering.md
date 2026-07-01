# Basic Tutorial 9: Media Information Gathering 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-9.c](../../src/basic-tutorial/basic-tutorial-9.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/media-information-gathering.html?gi-language=c>

这个 demo 的主题是 **媒体信息收集**：不真正播放媒体，只分析一个 URI 里包含什么内容、是否可播放、时长是多少、有哪些音视频流、metadata 是什么、是否支持 seek。

GStreamer 为这类需求提供了 `GstDiscoverer`，它位于 `pbutils` 库中。可以把它理解成一个“媒体探测器”：应用给它一个 URI，它帮你打开、解析、识别流信息，然后返回结构化结果。

## 这个 Demo 做了什么

程序默认探测这个 WebM 文件：

```text
https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

也可以通过命令行传入其他 URI：

```sh
./basic-tutorial-9 file:///path/to/video.mp4
./basic-tutorial-9 https://example.com/media.webm
```

它会打印：

- URI 是否有效、是否可播放。
- 媒体总时长。
- 全局 tags，例如容器格式、编码器、codec、语言、码率等。
- 是否支持 seek。
- stream topology，也就是容器、音频流、视频流、字幕流之间的层级结构。
- 每条 stream 的 caps、codec 描述和 tags。

这个 demo 是 `gst-discoverer-1.0` 工具的简化版。它只负责显示媒体信息，不做播放。

## 为什么需要 GstDiscoverer

如果没有 `GstDiscoverer`，应用也可以自己搭建一个 pipeline，让它进入 `PAUSED` 或 `PLAYING`，再监听 bus、查询 pads、读取 tags 和 caps。

但这会比较繁琐。很多应用只是想在播放前快速知道：

- 这个 URI 能不能播？
- 它是音频、视频还是容器文件？
- 有几路音轨、几路视频、几路字幕？
- 时长是多少？
- 缺不缺插件？

`GstDiscoverer` 把这些探测步骤封装好了。官方教程也说明，它支持同步和异步两种模式：

| 模式 | API | 特点 |
| --- | --- | --- |
| 同步 | `gst_discoverer_discover_uri()` | 调用会阻塞，直到探测完成 |
| 异步 | `gst_discoverer_discover_uri_async()` | 通过信号返回结果，适合 GUI 或事件驱动程序 |

这个 demo 使用异步模式。

## CustomData 数据结构

```c
typedef struct _CustomData {
  GstDiscoverer *discoverer;
  GMainLoop *loop;
} CustomData;
```

字段很少：

| 字段 | 作用 |
| --- | --- |
| `discoverer` | 媒体探测器对象 |
| `loop` | GLib 主循环，用来等待异步信号 |

因为程序没有播放管线，所以没有 `GstPipeline`、`GstBus`、sink、source 这些字段。

## main 函数流程

`main()` 的整体流程如下：

1. 选择要探测的 URI。
2. 初始化 `CustomData`。
3. 调用 `gst_init()` 初始化 GStreamer。
4. 创建 `GstDiscoverer`。
5. 连接 `discovered` 和 `finished` 信号。
6. 启动 discoverer。
7. 异步提交 URI。
8. 运行 GLib main loop，等待回调。
9. 探测完成后停止 discoverer 并释放资源。

## 选择 URI

```c
gchar *uri =
    "https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm";

if (argc > 1) {
  uri = argv[1];
}
```

如果命令行没有参数，就使用默认 WebM；如果有参数，就探测用户传入的 URI。

注意：GStreamer 的很多 API 要求 URI 是标准 URI 格式。本地文件通常要写成：

```text
file:///home/user/video.mp4
```

而不是普通路径：

```text
/home/user/video.mp4
```

## 创建 GstDiscoverer

```c
data.discoverer = gst_discoverer_new (5 * GST_SECOND, &err);
```

第一个参数是每个 URI 的探测超时时间，单位是纳秒。这里使用：

```c
5 * GST_SECOND
```

表示最多等待 5 秒。

如果创建失败，`err` 会包含错误信息：

```c
if (!data.discoverer) {
  g_print ("Error creating discoverer instance: %s\n", err->message);
  g_clear_error (&err);
  return -1;
}
```

`GstDiscoverer` 属于 `gstreamer-pbutils-1.0`，编译时需要链接这个库。

## 连接异步信号

```c
g_signal_connect (data.discoverer, "discovered",
    G_CALLBACK (on_discovered_cb), &data);
g_signal_connect (data.discoverer, "finished",
    G_CALLBACK (on_finished_cb), &data);
```

两个信号含义：

| 信号 | 触发时机 |
| --- | --- |
| `discovered` | 某个 URI 探测完成，结果可用 |
| `finished` | 所有提交的 URI 都探测完毕 |

这个 demo 只提交一个 URI，所以通常先收到一次 `discovered`，然后收到 `finished`。

如果一次提交多个 URI，就会收到多次 `discovered`，最后再收到一次 `finished`。

## 启动 Discoverer 并提交 URI

```c
gst_discoverer_start (data.discoverer);
```

这会启动 discoverer 的内部处理逻辑。此时还没有提交任何 URI。

接着异步提交 URI：

```c
if (!gst_discoverer_discover_uri_async (data.discoverer, uri)) {
  g_print ("Failed to start discovering URI '%s'\n", uri);
  g_object_unref (data.discoverer);
  return -1;
}
```

`gst_discoverer_discover_uri_async()` 只是把 URI 加入探测队列。它不会阻塞等待探测结果。真正的结果会通过 `discovered` 信号传给 `on_discovered_cb()`。

## GLib Main Loop

```c
data.loop = g_main_loop_new (NULL, FALSE);
g_main_loop_run (data.loop);
```

因为 discoverer 使用异步信号，程序必须运行 GLib main loop，信号回调才有机会被调度执行。

当所有 URI 探测完成后，`on_finished_cb()` 会调用：

```c
g_main_loop_quit (data->loop);
```

于是 `g_main_loop_run()` 返回，程序继续清理资源。

## on_discovered_cb：处理单个 URI 的探测结果

```c
static void on_discovered_cb (GstDiscoverer *discoverer,
    GstDiscovererInfo *info, GError *err, CustomData *data)
```

这个回调在某个 URI 探测完成时触发。核心参数是：

| 参数 | 含义 |
| --- | --- |
| `discoverer` | 发出信号的 `GstDiscoverer` |
| `info` | 当前 URI 的探测结果 |
| `err` | 错误信息，只有某些失败情况才有意义 |
| `data` | 用户数据，这里是 `CustomData` |

### 获取 URI 和结果枚举

```c
uri = gst_discoverer_info_get_uri (info);
result = gst_discoverer_info_get_result (info);
```

`GstDiscovererInfo` 包含该 URI 的完整探测结果。程序先取出 URI 和结果状态。

### 判断探测是否成功

```c
switch (result) {
  case GST_DISCOVERER_URI_INVALID:
    g_print ("Invalid URI '%s'\n", uri);
    break;
  case GST_DISCOVERER_ERROR:
    g_print ("Discoverer error: %s\n", err->message);
    break;
  case GST_DISCOVERER_TIMEOUT:
    g_print ("Timeout\n");
    break;
  case GST_DISCOVERER_BUSY:
    g_print ("Busy\n");
    break;
  case GST_DISCOVERER_MISSING_PLUGINS:
    ...
    break;
  case GST_DISCOVERER_OK:
    g_print ("Discovered '%s'\n", uri);
    break;
}
```

常见结果：

| 结果 | 含义 |
| --- | --- |
| `GST_DISCOVERER_OK` | 探测成功 |
| `GST_DISCOVERER_URI_INVALID` | URI 格式无效 |
| `GST_DISCOVERER_ERROR` | 探测过程中出错 |
| `GST_DISCOVERER_TIMEOUT` | 超时 |
| `GST_DISCOVERER_MISSING_PLUGINS` | 缺少解码或解析插件 |
| `GST_DISCOVERER_BUSY` | discoverer 忙，一般同步模式更可能出现 |

如果结果不是 `GST_DISCOVERER_OK`，程序认为该 URI 不能播放：

```c
if (result != GST_DISCOVERER_OK) {
  g_printerr ("This URI cannot be played\n");
  return;
}
```

### 缺少插件信息

```c
case GST_DISCOVERER_MISSING_PLUGINS:{
  const GstStructure *s;
  gchar *str;

  s = gst_discoverer_info_get_misc (info);
  str = gst_structure_to_string (s);

  g_print ("Missing plugins: %s\n", str);
  g_free (str);
  break;
}
```

当缺少插件时，`gst_discoverer_info_get_misc()` 可能提供额外结构化信息。demo 简单地把 `GstStructure` 转成字符串打印出来。

真实播放器可以用这些信息提示用户安装对应 codec 或插件包。

## 打印时长

```c
g_print ("\nDuration: %" GST_TIME_FORMAT "\n",
    GST_TIME_ARGS (gst_discoverer_info_get_duration (info)));
```

`gst_discoverer_info_get_duration()` 返回媒体总时长，单位是纳秒。

`GST_TIME_FORMAT` 和 `GST_TIME_ARGS()` 用来把纳秒时间打印成人类可读格式，例如：

```text
0:00:52.250000000
```

## 打印全局 Tags

```c
tags = gst_discoverer_info_get_tags (info);
if (tags) {
  g_print ("Tags:\n");
  gst_tag_list_foreach (tags, print_tag_foreach, GINT_TO_POINTER (1));
}
```

全局 tags 是媒体整体层面的 metadata，比如容器格式、编码器、应用名、码率等。

`gst_tag_list_foreach()` 会遍历 `GstTagList` 中的每个 tag，并调用：

```c
print_tag_foreach()
```

## print_tag_foreach：打印一个 Tag

```c
static void print_tag_foreach (const GstTagList *tags,
    const gchar *tag, gpointer user_data)
```

这个函数负责把 tag 打印成：

```text
tag nick: value
```

首先复制 tag 的值：

```c
GValue val = { 0, };
gst_tag_list_copy_value (&val, tags, tag);
```

`GValue` 是 GLib 的通用值容器，里面可能是字符串、整数、浮点数、日期等类型。

如果是字符串：

```c
if (G_VALUE_HOLDS_STRING (&val))
  str = g_value_dup_string (&val);
```

否则用 GStreamer 的序列化函数转成字符串：

```c
else
  str = gst_value_serialize (&val);
```

然后打印：

```c
g_print ("%*s%s: %s\n", 2 * depth, " ",
    gst_tag_get_nick (tag), str);
```

这里 `depth` 用于缩进，方便显示 stream topology 的层级。

最后释放：

```c
g_free (str);
g_value_unset (&val);
```

## 判断是否支持 Seek

```c
g_print ("Seekable: %s\n",
    (gst_discoverer_info_get_seekable (info) ? "yes" : "no"));
```

`gst_discoverer_info_get_seekable()` 表示该 URI 是否可 seek。

例如：

- 普通本地文件通常可 seek。
- 支持范围请求的 HTTP 媒体通常可 seek。
- 直播流通常不可 seek。

播放器可以用这个结果决定是否启用进度条拖动。

## Stream Information 与 Topology

```c
sinfo = gst_discoverer_info_get_stream_info (info);
if (!sinfo)
  return;

g_print ("Stream information:\n");
print_topology (sinfo, 1);
gst_discoverer_stream_info_unref (sinfo);
```

`gst_discoverer_info_get_stream_info()` 返回顶层 `GstDiscovererStreamInfo`。

它不是一个简单列表，而是一个拓扑结构。比如一个 WebM 文件大致可以理解为：

```text
container: WebM
  audio: Vorbis
  video: VP8
```

对于某些媒体，层级可能更复杂。`print_topology()` 用递归方式遍历这个结构。

## print_stream_info：打印单条 Stream

```c
static void print_stream_info (GstDiscovererStreamInfo *info, gint depth)
```

这个函数先获取 stream 的 caps：

```c
caps = gst_discoverer_stream_info_get_caps (info);
```

如果 caps 是固定的：

```c
if (gst_caps_is_fixed (caps))
  desc = gst_pb_utils_get_codec_description (caps);
```

`gst_pb_utils_get_codec_description()` 会把 caps 转成更友好的 codec 描述，例如 `VP8`、`Vorbis`、`WebM`。

如果 caps 不是固定 caps，就直接转字符串：

```c
else
  desc = gst_caps_to_string (caps);
```

然后打印 stream 类型和描述：

```c
g_print ("%*s%s: %s\n", 2 * depth, " ",
    gst_discoverer_stream_info_get_stream_type_nick (info),
    (desc ? desc : ""));
```

`gst_discoverer_stream_info_get_stream_type_nick()` 可能返回：

```text
container
audio
video
subtitle
```

之后再打印该 stream 自己的 tags：

```c
tags = gst_discoverer_stream_info_get_tags (info);
if (tags) {
  g_print ("%*sTags:\n", 2 * (depth + 1), " ");
  gst_tag_list_foreach (tags, print_tag_foreach,
      GINT_TO_POINTER (depth + 2));
}
```

注意：全局 tags 和 stream tags 不完全一样。全局 tags 描述整个媒体；stream tags 描述某一路音频、视频或字幕。

## print_topology：递归打印流拓扑

```c
static void print_topology (GstDiscovererStreamInfo *info, gint depth)
```

这个函数先打印当前 stream：

```c
print_stream_info (info, depth);
```

然后尝试获取“下一个” stream：

```c
next = gst_discoverer_stream_info_get_next (info);
if (next) {
  print_topology (next, depth + 1);
  gst_discoverer_stream_info_unref (next);
}
```

如果没有 next，但当前 stream 是容器：

```c
else if (GST_IS_DISCOVERER_CONTAINER_INFO (info)) {
  streams = gst_discoverer_container_info_get_streams
      (GST_DISCOVERER_CONTAINER_INFO (info));
  for (tmp = streams; tmp; tmp = tmp->next) {
    GstDiscovererStreamInfo *tmpinf =
        (GstDiscovererStreamInfo *) tmp->data;
    print_topology (tmpinf, depth + 1);
  }
  gst_discoverer_stream_info_list_free (streams);
}
```

就取出容器里的子 streams，并逐个递归打印。

这段 API 看起来有点绕，因为 stream topology 既可能通过 `next` 串起来，也可能是 container 里包含多个子流。demo 用递归把两种情况都处理了。

## on_finished_cb：所有 URI 探测完成

```c
static void on_finished_cb (GstDiscoverer *discoverer,
    CustomData *data) {
  g_print ("Finished discovering\n");
  g_main_loop_quit (data->loop);
}
```

`finished` 信号表示 discoverer 当前队列里的 URI 都处理完了。

这个 demo 只探测一个 URI，所以收到 `finished` 后就退出 main loop，程序结束。

## 资源清理

```c
gst_discoverer_stop (data.discoverer);
g_object_unref (data.discoverer);
g_main_loop_unref (data.loop);
```

清理顺序是：

1. 停止 discoverer。
2. 释放 discoverer 对象。
3. 释放 GLib main loop。

## 编译提示

这个 demo 使用了 `gst/pbutils/pbutils.h`，所以除了 `gstreamer-1.0`，还需要链接 `gstreamer-pbutils-1.0`。

Linux 下可类似这样编译：

```sh
gcc src/basic-tutorial/basic-tutorial-9.c -o bin/basic-tutorial-9 \
  `pkg-config --cflags --libs gstreamer-1.0 gstreamer-pbutils-1.0`
```

如果缺少 `gstreamer-pbutils-1.0`，会出现头文件或链接错误。

## 运行时可能看到什么

对默认 Sintel WebM，输出大致类似：

```text
Discovering 'https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm'
Discovered 'https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm'

Duration: 0:00:52.250000000
Tags:
  video codec: On2 VP8
  language code: en
  container format: Matroska
  audio codec: Vorbis
  bitrate: 80000
Seekable: yes

Stream information:
  container: WebM
    audio: Vorbis
      Tags:
        language code: en
        audio codec: Vorbis
    video: VP8
      Tags:
        video codec: VP8 video

Finished discovering
```

实际 tag 数量和 codec 描述可能随 GStreamer 版本、插件和媒体文件而不同。

## 关键 API 总结

| API / 概念 | 作用 |
| --- | --- |
| `GstDiscoverer` | GStreamer 的媒体信息探测器 |
| `gst_discoverer_new()` | 创建 discoverer，并设置单个 URI 的超时 |
| `gst_discoverer_start()` | 启动异步探测服务 |
| `gst_discoverer_discover_uri_async()` | 异步提交一个 URI |
| `discovered` 信号 | 单个 URI 探测完成时触发 |
| `finished` 信号 | 队列中所有 URI 探测完成时触发 |
| `GstDiscovererInfo` | 单个 URI 的探测结果 |
| `gst_discoverer_info_get_result()` | 获取探测结果状态 |
| `gst_discoverer_info_get_duration()` | 获取媒体时长 |
| `gst_discoverer_info_get_tags()` | 获取全局 tags |
| `gst_discoverer_info_get_seekable()` | 判断是否支持 seek |
| `gst_discoverer_info_get_stream_info()` | 获取顶层 stream info |
| `GstDiscovererStreamInfo` | 单条 stream 的信息 |
| `gst_discoverer_stream_info_get_caps()` | 获取 stream caps |
| `gst_pb_utils_get_codec_description()` | 把 caps 转成友好的 codec 描述 |
| `gst_discoverer_stream_info_get_tags()` | 获取 stream tags |
| `GstDiscovererContainerInfo` | 容器 stream 信息，可包含子 streams |
| `gst_discoverer_container_info_get_streams()` | 获取容器里的子 streams |
| `GstTagList` | metadata 列表 |
| `gst_tag_list_foreach()` | 遍历 tags |
| `gst_tag_get_nick()` | 获取 tag 的可读名称 |

## 这篇教程的核心思想

`GstDiscoverer` 适合做播放前的媒体探测。它可以帮应用快速回答：

- 这个 URI 是否可播放？
- 是否缺少插件？
- 媒体时长是多少？
- 是否支持 seek？
- 有哪些音频、视频、字幕流？
- 每条流的 codec、caps、tags 是什么？

播放器、媒体库、转码工具、文件导入器、上传校验服务都经常需要这类能力。真正播放前先 discover 一遍，可以让应用更早发现问题，也能提前准备 UI、音轨列表、字幕列表和错误提示。

## 可尝试的改动

- 传入本地文件 URI，比较不同容器和 codec 的输出。
- 提交多个 URI，观察多次 `discovered` 和一次 `finished` 的顺序。
- 在 `GST_DISCOVERER_MISSING_PLUGINS` 分支里打印更详细的插件安装信息。
- 只提取视频宽高、音频采样率等字段，用于生成媒体库索引。
- 改用同步 API `gst_discoverer_discover_uri()`，观察代码结构和阻塞行为的差异。

