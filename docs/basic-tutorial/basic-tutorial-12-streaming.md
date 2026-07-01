# Basic Tutorial 12: Streaming 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-12.c](../../src/basic-tutorial/basic-tutorial-12.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/streaming.html?gi-language=c>

这个 demo 的主题是 **网络流媒体播放**。这里的 streaming 指的是：媒体数据不先完整下载到本地文件，而是一边从网络接收，一边解码、排队、播放。

前面的教程里其实已经多次播放过 HTTP URI，例如 Sintel trailer。第 12 篇重点补上两个网络播放时必须处理的问题：

- **Buffering**：网络数据到达速度不稳定，需要先缓存一部分再播放。
- **Clock lost**：播放过程中时钟丢失时，需要让 pipeline 重新选择时钟。

## 这个 Demo 做了什么

程序使用 `playbin` 播放远程 WebM 文件：

```text
https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

和 Basic Tutorial 1 类似，它没有手动创建 demuxer、decoder、sink，而是直接用：

```c
pipeline = gst_parse_launch (
    "playbin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm",
    NULL);
```

不同点在于：这次程序不只是等待 `ERROR` 和 `EOS`，还专门监听并处理：

- `GST_MESSAGE_BUFFERING`
- `GST_MESSAGE_CLOCK_LOST`

这两个消息就是本教程的核心。

## 管线结构

代码里看起来只创建了一个 `playbin`：

```text
playbin uri=https://...
```

但 `playbin` 内部会自动搭建完整播放管线，大致包括：

```text
网络 source -> demuxer -> decoder -> converter -> audio/video sink
```

对于 HTTP/WebM 文件，内部可能涉及：

- 网络读取 element。
- WebM/Matroska demuxer。
- VP8 视频解码器。
- Vorbis 音频解码器。
- 音视频 converter。
- 音频 sink 和视频 sink。
- `queue2` / `multiqueue` 等缓冲相关 element。

本教程关心的不是这些内部 element 具体是哪一个，而是应用如何响应它们发到 bus 上的消息。

## CustomData 数据结构

```c
typedef struct _CustomData {
  gboolean is_live;
  GstElement *pipeline;
  GMainLoop *loop;
} CustomData;
```

字段含义：

| 字段 | 作用 |
| --- | --- |
| `is_live` | 当前媒体是否是 live stream |
| `pipeline` | 这里实际是 `playbin` 创建出的顶层 element |
| `loop` | GLib 主循环，用于等待 bus 消息 |

`is_live` 是本教程的一个关键变量。live stream 和普通点播文件在 buffering 行为上不一样，后面会展开讲。

## gst_parse_launch

这个 demo 没有用：

```c
gst_element_factory_make ("playbin", "playbin");
g_object_set (playbin, "uri", ..., NULL);
```

而是使用：

```c
pipeline = gst_parse_launch (
    "playbin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm",
    NULL);
```

`gst_parse_launch()` 可以把类似 `gst-launch-1.0` 的 pipeline 字符串解析成真实的 GStreamer element。

它适合：

- 快速构建简单 demo。
- 把已经用 `gst-launch-1.0` 验证过的管线搬进代码。
- 动态加载用户提供的 pipeline 描述。

本例中的字符串只有一个 `playbin`，所以非常简单。

## 启动播放并识别 Live Stream

```c
ret = gst_element_set_state (pipeline, GST_STATE_PLAYING);
if (ret == GST_STATE_CHANGE_FAILURE) {
  g_printerr ("Unable to set the pipeline to the playing state.\n");
  gst_object_unref (pipeline);
  return -1;
} else if (ret == GST_STATE_CHANGE_NO_PREROLL) {
  data.is_live = TRUE;
}
```

这里除了判断失败，还特别检查：

```c
GST_STATE_CHANGE_NO_PREROLL
```

这是 live stream 的重要信号。

普通文件或 HTTP 点播流通常可以 preroll：pipeline 进入 `PAUSED` 状态时，能够提前准备好第一批数据，等待真正进入 `PLAYING`。

live stream 不一样。直播流没有“从头开始的一段固定媒体”，暂停也不能让它像文件一样停在某个可重复的位置。因此 live stream 在 `PAUSED` 状态下通常表现得更像 `PLAYING`，状态切换会返回 `GST_STATE_CHANGE_NO_PREROLL`。

虽然代码直接请求的是 `PLAYING`，但状态变化内部会经过：

```text
NULL -> READY -> PAUSED -> PLAYING
```

所以如果中途发现没有 preroll，就可能返回 `NO_PREROLL`。demo 用它设置：

```c
data.is_live = TRUE;
```

## 为什么 Live Stream 不处理 Buffering

代码中处理 buffering 前会先判断：

```c
if (data->is_live) break;
```

原因是：live stream 不适合用普通点播那套“暂停等待缓存到 100% 再播放”的策略。

对于点播文件：

```text
网络慢 -> 先暂停播放 -> 缓冲增长 -> 到 100% 后继续播放
```

这很合理，因为媒体内容是固定的，暂停以后还可以从当前位置继续。

但对于直播：

```text
直播内容不断向前走
```

如果为了攒缓存而暂停，可能带来越来越大的延迟，甚至没有明确的“缓存到 100%”概念。因此 demo 对 live stream 直接忽略 buffering 消息。

## Bus Signal Watch

程序获取 bus：

```c
bus = gst_element_get_bus (pipeline);
```

然后使用 signal watch：

```c
gst_bus_add_signal_watch (bus);
g_signal_connect (bus, "message", G_CALLBACK (cb_message), &data);
```

这和 Basic Tutorial 5、8、9 类似，都是把 GStreamer bus 集成到 GLib main loop。

不同的是，这里连接的是通用：

```text
message
```

而不是 `message::error`、`message::eos` 这种具体消息类型。所以所有 bus 消息都会进入：

```c
cb_message()
```

再由回调内部 `switch` 判断消息类型。

## GLib Main Loop

```c
main_loop = g_main_loop_new (NULL, FALSE);
data.loop = main_loop;
data.pipeline = pipeline;

g_main_loop_run (main_loop);
```

因为 bus 使用 signal watch，程序需要运行 GLib main loop，bus 消息回调才会被调度。

当收到错误或 EOS 时，回调中会调用：

```c
g_main_loop_quit (data->loop);
```

于是主循环退出，程序继续执行资源清理。

## cb_message 消息处理

```c
static void cb_message (GstBus *bus, GstMessage *msg, CustomData *data)
```

这个函数处理本教程关心的 bus 消息：

- `GST_MESSAGE_ERROR`
- `GST_MESSAGE_EOS`
- `GST_MESSAGE_BUFFERING`
- `GST_MESSAGE_CLOCK_LOST`

## ERROR 处理

```c
case GST_MESSAGE_ERROR: {
  GError *err;
  gchar *debug;

  gst_message_parse_error (msg, &err, &debug);
  g_print ("Error: %s\n", err->message);
  g_error_free (err);
  g_free (debug);

  gst_element_set_state (data->pipeline, GST_STATE_READY);
  g_main_loop_quit (data->loop);
  break;
}
```

发生错误时：

1. 用 `gst_message_parse_error()` 取出错误信息。
2. 打印错误。
3. 把 pipeline 设置为 `READY`，停止播放。
4. 退出 main loop。

这里的 demo 没有打印 `debug` 字符串，只释放了它。实际项目中通常建议也打印 debug 信息，能帮助定位具体 element 和内部错误原因。

## EOS 处理

```c
case GST_MESSAGE_EOS:
  gst_element_set_state (data->pipeline, GST_STATE_READY);
  g_main_loop_quit (data->loop);
  break;
```

`EOS` 是 End Of Stream，表示媒体播放结束。

收到后同样：

1. 设置 pipeline 到 `READY`。
2. 退出 main loop。

对于默认 Sintel trailer 这种点播媒体，播放到结尾后会触发 EOS。对于直播流，通常不会自然 EOS。

## BUFFERING 处理

这是本教程最重要的部分：

```c
case GST_MESSAGE_BUFFERING: {
  gint percent = 0;

  if (data->is_live) break;

  gst_message_parse_buffering (msg, &percent);
  g_print ("Buffering (%3d%%)\r", percent);

  if (percent < 100)
    gst_element_set_state (data->pipeline, GST_STATE_PAUSED);
  else
    gst_element_set_state (data->pipeline, GST_STATE_PLAYING);
  break;
}
```

### BUFFERING 消息来自哪里

网络播放时，数据从网络到达速度可能忽快忽慢。GStreamer 内部的一些 element，例如 `queue2`、`multiqueue`，可以维护缓冲区，并向 bus 发送 buffering 百分比。

这个百分比表示当前缓冲程度：

```text
0%   缓冲很少
100% 缓冲足够，可以播放
```

### 解析百分比

```c
gst_message_parse_buffering (msg, &percent);
```

`percent` 是整数，范围通常是 0 到 100。

### 低于 100% 时暂停

```c
if (percent < 100)
  gst_element_set_state (data->pipeline, GST_STATE_PAUSED);
```

如果缓冲没满，程序把 pipeline 设置为 `PAUSED`。这样播放暂停，内部 buffering element 继续接收网络数据、积累缓冲。

### 到 100% 后继续播放

```c
else
  gst_element_set_state (data->pipeline, GST_STATE_PLAYING);
```

缓冲到 100% 后，恢复播放。

这套逻辑能改善网络抖动体验：

```text
网络慢 -> 缓冲下降 -> 暂停播放
网络恢复 -> 缓冲增长到 100% -> 继续播放
```

如果网络足够快，可能几乎看不到 buffering 百分比变化，因为缓冲很快就完成。

## 为什么要暂停而不是继续播放

如果缓冲不足还继续播放，下游 sink 可能很快没有数据可播放，表现为：

- 视频卡住。
- 音频断续。
- 播放时停时走。

主动暂停到缓冲足够，虽然会增加一点等待时间，但通常能换来更平滑的播放体验。

这就是流媒体播放器常见的“正在缓冲”行为。

## CLOCK_LOST 处理

另一个网络播放相关消息是：

```c
case GST_MESSAGE_CLOCK_LOST:
  gst_element_set_state (data->pipeline, GST_STATE_PAUSED);
  gst_element_set_state (data->pipeline, GST_STATE_PLAYING);
  break;
```

GStreamer 为了让多个 sink 同步播放，会选择一个全局 clock。例如音频 sink 可能提供 clock，视频 sink 根据它同步显示。

某些情况下 clock 可能丢失，例如：

- RTP source 切换流。
- 输出设备变化。
- streaming source 或 sink 重新配置。
- 某个提供 clock 的 element 消失或状态变化。

收到 `GST_MESSAGE_CLOCK_LOST` 后，应用只需要做一件事：

```text
PAUSED -> PLAYING
```

也就是让 pipeline 重新经过一次时钟选择流程。GStreamer 会选择新的 clock，然后恢复播放。

## 资源清理

主循环退出后：

```c
g_main_loop_unref (main_loop);
gst_object_unref (bus);
gst_element_set_state (pipeline, GST_STATE_NULL);
gst_object_unref (pipeline);
```

清理顺序：

1. 释放 GLib main loop。
2. 释放 bus。
3. 把 pipeline 设置为 `NULL`，释放运行时资源。
4. 释放 pipeline 对象。

实际项目里也可以在退出前调用 `gst_bus_remove_signal_watch()`，与 `gst_bus_add_signal_watch()` 对应。这个 demo 简化处理，随后整个 pipeline 和 bus 都会被释放。

## 运行时可能看到什么

运行后会打开视频窗口并播放网络媒体。终端可能看到：

```text
Buffering (  0%)
Buffering ( 21%)
Buffering ( 74%)
Buffering (100%)
```

如果网络很快，buffering 变化可能一闪而过，甚至几乎看不到。

播放结束后，程序收到 EOS 并退出。

## 编译提示

这个 demo 只需要 GStreamer core 库：

```sh
gcc src/basic-tutorial/basic-tutorial-12.c -o bin/basic-tutorial-12 \
  `pkg-config --cflags --libs gstreamer-1.0`
```

运行时需要有能处理远程 HTTP/WebM/VP8/Vorbis 的相关 GStreamer 插件。缺少插件时，`playbin` 可能无法完成播放，可以用：

```sh
GST_DEBUG=2 ./bin/basic-tutorial-12
gst-discoverer-1.0 https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm -v
```

来查看错误和缺失插件信息。

## 和前面教程的关系

| 概念 | 前面对应教程 | 本教程补充 |
| --- | --- | --- |
| `playbin` | Basic Tutorial 1、4、5 | 用 `gst_parse_launch()` 创建并播放网络 URI |
| bus 消息 | Basic Tutorial 2、3、4 | 增加 `BUFFERING` 和 `CLOCK_LOST` |
| GLib main loop | Basic Tutorial 5、8、9 | 用 bus signal watch 异步处理 streaming 消息 |
| 时间和状态 | Basic Tutorial 4 | 根据 buffering 百分比切换 `PAUSED/PLAYING` |
| 调试 | Basic Tutorial 10、11 | 网络播放失败时可用 `GST_DEBUG` 和 `gst-discoverer-1.0` 排查 |

## 关键 API 总结

| API / 消息 | 作用 |
| --- | --- |
| `gst_parse_launch()` | 从 pipeline 描述字符串创建 element/pipeline |
| `playbin uri=...` | 自动搭建网络媒体播放管线 |
| `gst_element_set_state()` | 切换 pipeline 状态 |
| `GST_STATE_CHANGE_NO_PREROLL` | 状态切换返回值，常用于识别 live stream |
| `gst_element_get_bus()` | 获取 pipeline 的 bus |
| `gst_bus_add_signal_watch()` | 把 bus 消息接入 GLib main loop |
| `GST_MESSAGE_BUFFERING` | 缓冲进度消息 |
| `gst_message_parse_buffering()` | 解析 buffering 百分比 |
| `GST_MESSAGE_CLOCK_LOST` | pipeline 使用的 clock 丢失 |
| `GST_MESSAGE_ERROR` | 错误消息 |
| `GST_MESSAGE_EOS` | 媒体播放结束 |
| `g_main_loop_new()` | 创建 GLib main loop |
| `g_main_loop_run()` | 运行主循环等待消息 |
| `g_main_loop_quit()` | 退出主循环 |

## 这篇教程的核心思想

网络播放和本地文件播放最大的区别是：数据到达时间不稳定。

因此应用应该额外处理两类消息：

- `GST_MESSAGE_BUFFERING`：缓冲不足时暂停播放，缓冲到 100% 后恢复播放。
- `GST_MESSAGE_CLOCK_LOST`：时钟丢失时让 pipeline 从 `PAUSED` 回到 `PLAYING`，重新选择时钟。

这两点代码量很少，但对网络播放体验影响很大。真实播放器里，buffering 百分比还可以用来更新 UI，例如显示“正在缓冲 42%”，并在 live stream 场景下采用不同策略。

## 可尝试的改动

- 把 URI 换成一个较慢的网络地址，观察 buffering 消息。
- 在 `ERROR` 分支里打印 `debug` 字符串，获取更详细错误信息。
- 在 UI 中显示 buffering 百分比，而不是只打印到终端。
- 尝试播放直播流，观察 `GST_STATE_CHANGE_NO_PREROLL` 和 `is_live` 行为。
- 用 `GST_DEBUG=2,queue2*:5,multiqueue*:5` 观察内部缓冲行为。

