# Basic Tutorial 13: Playback Speed 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-13.c](../../src/basic-tutorial/basic-tutorial-13.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/playback-speed.html?gi-language=c>

这个 demo 的主题是 **播放速度控制**，也就是 trick modes：快进、慢放、倒放，以及逐帧播放。

GStreamer 里改变播放速度常见有两种机制：

- **Seek Event**：通过 seek 事件设置新的播放 rate，可以正放、倒放、快放、慢放。
- **Step Event**：让 sink 向前推进指定数量的数据，例如逐帧播放一个视频帧。

本 demo 主要用 seek event 改变播放速度，用 step event 做单帧前进。

## 这个 Demo 做了什么

程序使用 `playbin` 播放远程 WebM 文件：

```text
https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

运行后，终端会提示可以输入命令：

```text
'P' to toggle between PAUSE and PLAY
'S' to increase playback speed, 's' to decrease playback speed
'D' to toggle playback direction
'N' to move to next frame (in the current direction, better in PAUSE)
'Q' to quit
```

这些按键含义：

| 按键 | 作用 |
| --- | --- |
| `P` / `p` | 在播放和暂停之间切换 |
| `S` | 播放速度乘以 2 |
| `s` | 播放速度除以 2 |
| `D` / `d` | 播放方向取反，正放变倒放，倒放变正放 |
| `N` / `n` | 推进一帧，通常暂停状态下更好观察 |
| `Q` / `q` | 退出程序 |

例如：

- 初始 rate 是 `1.0`，正常播放。
- 按 `S` 后 rate 变成 `2.0`，2 倍速。
- 再按 `S` 后 rate 变成 `4.0`，4 倍速。
- 按 `s` 后 rate 变成 `2.0`。
- 按 `D` 后 rate 变成 `-2.0`，2 倍速倒放。

## Playback Rate 是什么

播放速度用一个浮点数 `rate` 表示：

| Rate | 含义 |
| --- | --- |
| `1.0` | 正常正向播放 |
| `2.0` | 2 倍速正向播放 |
| `0.5` | 半速慢放 |
| `-1.0` | 正常速度倒放 |
| `-2.0` | 2 倍速倒放 |

规则是：

- 绝对值越大，播放越快。
- 绝对值小于 1，播放越慢。
- 正数表示正向播放。
- 负数表示反向播放。

不是所有媒体、协议、demuxer、decoder、sink 都能很好支持所有 trick modes。官方教程特别提醒：改变播放速度可能只对本地文件可靠；如果远程 URI 不能变速，可以改用 `file:///...` 本地文件测试。

## CustomData 数据结构

```c
typedef struct _CustomData
{
  GstElement *pipeline;
  GstElement *video_sink;
  GMainLoop *loop;

  gboolean playing;
  gdouble rate;
} CustomData;
```

字段含义：

| 字段 | 作用 |
| --- | --- |
| `pipeline` | 这里是通过 `gst_parse_launch()` 创建的 `playbin` |
| `video_sink` | 从 `playbin` 获取到的视频 sink，用来发送 seek/step event |
| `loop` | GLib 主循环 |
| `playing` | 当前是播放还是暂停 |
| `rate` | 当前播放速度，可以为负数 |

`video_sink` 初始为 `NULL`，直到第一次需要发送 seek 或 step event 时，才从 `playbin` 的 `video-sink` 属性里取出来。

## main / tutorial_main 流程

主要流程如下：

1. 调用 `gst_init()` 初始化 GStreamer。
2. 清空 `CustomData`。
3. 打印键盘操作说明。
4. 用 `gst_parse_launch()` 创建 `playbin`。
5. 给标准输入安装 GLib I/O watch，用于读取键盘命令。
6. 设置 pipeline 到 `PLAYING`。
7. 初始化 `playing = TRUE`、`rate = 1.0`。
8. 进入 GLib main loop。
9. 退出时释放 main loop、stdin channel、video sink 和 pipeline。

## 用 gst_parse_launch 创建 playbin

```c
data.pipeline =
    gst_parse_launch
    ("playbin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm",
    NULL);
```

`gst_parse_launch()` 可以解析类似 `gst-launch-1.0` 的 pipeline 字符串。

这里等价于从命令行运行：

```sh
gst-launch-1.0 playbin uri=https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

`playbin` 内部会自动创建网络 source、demuxer、decoder、converter 和音视频 sink。

## 监听键盘输入

Linux/Unix 下：

```c
io_stdin = g_io_channel_unix_new (fileno (stdin));
```

Windows 下：

```c
io_stdin = g_io_channel_win32_new_fd (fileno (stdin));
```

然后安装 watch：

```c
g_io_add_watch (io_stdin, G_IO_IN,
    (GIOFunc) handle_keyboard, &data);
```

含义是：当 stdin 有输入时，GLib main loop 会调用：

```c
handle_keyboard()
```

所以这个 demo 不需要自己写阻塞式 `scanf()` 循环，键盘输入和 GStreamer 播放都在 GLib 事件循环里协同工作。

## handle_keyboard：处理命令

```c
static gboolean
handle_keyboard (GIOChannel * source, GIOCondition cond, CustomData * data)
```

这个函数先读取一行：

```c
g_io_channel_read_line (source, &str, NULL, NULL, NULL)
```

然后只看第一个字符：

```c
switch (g_ascii_tolower (str[0])) {
```

`g_ascii_tolower()` 让 `P` 和 `p` 进入同一个 case，`S` 和 `s` 也进入同一个 case。对于 `S/s`，代码再用 `g_ascii_isupper()` 区分大小写。

函数最后返回：

```c
return TRUE;
```

表示这个 I/O watch 继续保留，下次 stdin 有输入时还会再次调用。

## P：播放 / 暂停切换

```c
case 'p':
  data->playing = !data->playing;
  gst_element_set_state (data->pipeline,
      data->playing ? GST_STATE_PLAYING : GST_STATE_PAUSED);
  g_print ("Setting state to %s\n",
      data->playing ? "PLAYING" : "PAUSE");
  break;
```

这部分和前面教程一样，就是切换 pipeline 状态：

```text
PLAYING <-> PAUSED
```

暂停后画面停住，但 pipeline 仍保留当前上下文，适合配合 `N` 做逐帧播放。

## S / s：增加或降低播放速度

```c
case 's':
  if (g_ascii_isupper (str[0])) {
    data->rate *= 2.0;
  } else {
    data->rate /= 2.0;
  }
  send_seek_event (data);
  break;
```

逻辑：

- 输入大写 `S`：速度乘以 2。
- 输入小写 `s`：速度除以 2。

改变 `data->rate` 后，调用：

```c
send_seek_event (data);
```

注意：真正让 GStreamer 改变播放速度的不是改变量本身，而是后面发送的 seek event。

## D：切换播放方向

```c
case 'd':
  data->rate *= -1.0;
  send_seek_event (data);
  break;
```

乘以 `-1.0` 会反转方向：

```text
 1.0 -> -1.0
 2.0 -> -2.0
-0.5 ->  0.5
```

然后同样通过 `send_seek_event()` 发出新的 seek event。

倒放不是所有 element 都支持得很好。常见限制包括：

- 网络流可能无法倒放。
- 某些 demuxer 或 decoder 不支持反向处理。
- 帧间编码视频倒放成本高，因为很多帧依赖前后关键帧。

如果倒放失败，建议先用本地文件 URI 测试。

## 为什么改变速度要发送 Seek Event

直觉上，改变速度似乎只要设置一个属性：

```text
rate = 2.0
```

但 GStreamer 的播放速度是通过事件传递给 pipeline 的。`Seek Event` 不只表示“跳转到某个位置”，它还包含：

- 新的 playback rate。
- 时间格式。
- seek flags。
- 新 segment 的 start 和 stop。

所以这个 demo 虽然不想真的跳到另一个位置，也仍然要发送 seek event。它的做法是：

```text
先查询当前位置
再 seek 到当前位置
同时设置新的 rate
```

这样用户感觉上没有跳转，只是从当前点开始用新的速度继续播放。

## send_seek_event：改变播放速度的核心

```c
static void
send_seek_event (CustomData * data)
```

这个函数的流程：

1. 查询当前播放位置。
2. 根据正向或反向播放构造不同 seek event。
3. 获取 `playbin` 当前使用的视频 sink。
4. 把 seek event 发送给 video sink。
5. 打印当前 rate。

### 查询当前位置

```c
if (!gst_element_query_position (data->pipeline,
    GST_FORMAT_TIME, &position)) {
  g_printerr ("Unable to retrieve current position.\n");
  return;
}
```

`position` 是当前播放位置，单位是纳秒。

这一步非常重要，因为我们想从当前点继续播放，而不是跳到别的位置。

## gst_event_new_seek 参数

函数原型概念上可以理解为：

```c
gst_event_new_seek (
    rate,
    format,
    flags,
    start_type, start,
    stop_type, stop);
```

本 demo 使用：

```c
GST_FORMAT_TIME
```

表示 start/stop 都是时间位置。

使用的 flags 是：

```c
GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE
```

含义：

| Flag | 作用 |
| --- | --- |
| `GST_SEEK_FLAG_FLUSH` | 清空旧数据，让 seek 更快生效 |
| `GST_SEEK_FLAG_ACCURATE` | 尽量精确 seek 到目标位置 |

`ACCURATE` 比 `KEY_UNIT` 更追求精确，但可能更慢。对变速/倒放演示来说，精确位置更容易理解。

## 正向播放的 Seek Event

```c
if (data->rate > 0) {
  seek_event =
      gst_event_new_seek (data->rate, GST_FORMAT_TIME,
      GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE,
      GST_SEEK_TYPE_SET, position,
      GST_SEEK_TYPE_END, 0);
}
```

正向播放时：

```text
start = 当前 position
stop  = stream 末尾
rate  > 0
```

也就是从当前位置开始，按正向播放到结尾。

`GST_SEEK_TYPE_END, 0` 表示 stop 位置是“距离 stream 结尾 0”，即结尾。

## 反向播放的 Seek Event

```c
else {
  seek_event =
      gst_event_new_seek (data->rate, GST_FORMAT_TIME,
      GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE,
      GST_SEEK_TYPE_SET, 0,
      GST_SEEK_TYPE_SET, position);
}
```

反向播放时：

```text
start = 0
stop  = 当前 position
rate  < 0
```

也就是在 `[0, position]` 这个 segment 内反向播放，从当前 position 往 0 方向走。

这里容易误解：即使是反向播放，seek event 里的 start 也应该小于 stop。方向由 `rate` 的正负决定，不是靠 start/stop 大小倒过来表达。

## 为什么把 Event 发给 video_sink

```c
if (data->video_sink == NULL) {
  g_object_get (data->pipeline, "video-sink",
      &data->video_sink, NULL);
}

gst_element_send_event (data->video_sink, seek_event);
```

官方教程特别说明：不要直接把 seek event 发给 `playbin`。

原因是 `playbin` 是一个 bin，内部可能有多个 sink，例如：

```text
audio sink
video sink
subtitle sink
```

如果把 event 发给 `playbin`，它可能把 event 分发到多个 sink，导致多个 seek 被执行。常见做法是从 `playbin` 取出一个实际 sink，比如 `video-sink` 或 `audio-sink`，然后把 event 发给这个 sink。

这里选择 `video-sink`：

```c
g_object_get (data->pipeline, "video-sink", &data->video_sink, NULL);
```

这个操作没有放在初始化阶段，而是在第一次需要时才做，是因为 `playbin` 的实际 sink 可能要等媒体读取和 pipeline 进入运行状态后才确定。

## N：逐帧播放

```c
case 'n':
  if (data->video_sink == NULL) {
    g_object_get (data->pipeline, "video-sink",
        &data->video_sink, NULL);
  }

  gst_element_send_event (data->video_sink,
      gst_event_new_step (GST_FORMAT_BUFFERS, 1,
          ABS (data->rate), TRUE, FALSE));
  g_print ("Stepping one frame\n");
  break;
```

逐帧播放使用的是 step event：

```c
gst_event_new_step (GST_FORMAT_BUFFERS, 1,
    ABS (data->rate), TRUE, FALSE)
```

参数含义：

| 参数 | 含义 |
| --- | --- |
| `GST_FORMAT_BUFFERS` | 以 buffer 数量为单位 step |
| `1` | 推进 1 个 buffer。对视频 sink 来说通常就是 1 帧 |
| `ABS (data->rate)` | step 时使用当前速度的绝对值 |
| `TRUE` | flush，清掉旧数据，让 step 立即生效 |
| `FALSE` | intermediate，表示这不是中间 step |

官方教程提醒：frame stepping 通常应先暂停，再按 `N`。如果 pipeline 还在 `PLAYING`，画面本来就在连续播放，单帧推进不容易观察。

Step event 有一个限制：它不能改变播放方向。所以这里传入的是：

```c
ABS (data->rate)
```

方向仍然由当前 segment/rate 状态决定；step event 本身只表达推进多少数据和速度。

## Step Event 和 Seek Event 的区别

| 机制 | 优点 | 限制 |
| --- | --- | --- |
| Seek Event | 可以设置正负 rate，可以跳到任意位置，事件会向上游传播 | 参数较多，处理成本较高 |
| Step Event | 参数少，响应快，适合单帧推进 | 主要作用于 sink，不能改变播放方向 |

官方教程选择 seek event 来改变 rate，是因为 seek event 会沿 pipeline 向上游传播，让 demuxer、decoder 等 element 都有机会响应新的 rate。Step event 只作用在 sink 端，如果上游不配合，变速效果就不可靠。

## Q：退出程序

```c
case 'q':
  g_main_loop_quit (data->loop);
  break;
```

退出 GLib main loop 后，`tutorial_main()` 继续执行资源释放。

## 资源清理

```c
g_main_loop_unref (data.loop);
g_io_channel_unref (io_stdin);
gst_element_set_state (data.pipeline, GST_STATE_NULL);
if (data.video_sink != NULL)
  gst_object_unref (data.video_sink);
gst_object_unref (data.pipeline);
```

清理顺序：

1. 释放 GLib main loop。
2. 释放 stdin 对应的 `GIOChannel`。
3. 把 pipeline 设置为 `NULL`，停止播放并释放运行资源。
4. 如果取过 `video_sink`，释放它的引用。
5. 释放 pipeline。

## 运行时可能看到什么

启动后终端会显示操作说明，然后打开视频窗口并播放网络视频。

输入命令后可能看到：

```text
S
Current rate: 2
s
Current rate: 1
D
Current rate: -1
P
Setting state to PAUSE
N
Stepping one frame
Q
```

注意输入命令后要按 Enter，因为程序读取的是一行 stdin。

如果变速或倒放不生效，优先尝试本地文件：

```c
"playbin uri=file:///home/user/sintel_trailer-480p.webm"
```

网络流、某些容器或某些 decoder 对倒放和变速支持可能有限。

## 编译提示

这个 demo 只需要 GStreamer core 库：

```sh
gcc src/basic-tutorial/basic-tutorial-13.c -o bin/basic-tutorial-13 \
  `pkg-config --cflags --libs gstreamer-1.0`
```

运行时需要能播放默认 WebM 的相关插件。排错时可以用：

```sh
GST_DEBUG=2 ./bin/basic-tutorial-13
GST_DEBUG=2,GST_EVENT:5,GST_SEEK:5 ./bin/basic-tutorial-13
```

观察 seek 和 event 相关日志。

## 和前面教程的关系

| 概念 | 前面对应教程 | 本教程补充 |
| --- | --- | --- |
| `playbin` | Basic Tutorial 1、4、5、12 | 用 `playbin` 做 trick mode 播放 |
| 查询 position | Basic Tutorial 4 | 变速前先查询当前位置 |
| seek | Basic Tutorial 4 | 不再用 `gst_element_seek_simple()`，而是手动创建 seek event |
| GLib main loop | Basic Tutorial 5、8、9、12 | 用 GIO watch 监听键盘输入 |
| event | 前面隐式使用较多 | 显式创建并发送 seek/step event |
| 调试 | Basic Tutorial 11 | 可用 `GST_EVENT`、`GST_SEEK` category 观察事件流 |

## 关键 API 总结

| API / 概念 | 作用 |
| --- | --- |
| `gst_parse_launch()` | 从 pipeline 字符串创建 `playbin` |
| `g_io_channel_unix_new()` | Unix 下把 stdin 包装成 GLib I/O channel |
| `g_io_channel_win32_new_fd()` | Windows 下把 stdin 包装成 GLib I/O channel |
| `g_io_add_watch()` | 在 GLib main loop 中监听 stdin 输入 |
| `g_io_channel_read_line()` | 读取一行键盘输入 |
| `gst_element_query_position()` | 查询当前播放位置 |
| `gst_event_new_seek()` | 创建 seek event，用于改变 rate 和 segment |
| `GST_SEEK_FLAG_FLUSH` | 清空旧数据，让 seek 更快生效 |
| `GST_SEEK_FLAG_ACCURATE` | 尽量精确 seek 到目标位置 |
| `GST_SEEK_TYPE_SET` | start/stop 使用明确位置 |
| `GST_SEEK_TYPE_END` | 位置相对于 stream 结尾 |
| `gst_element_send_event()` | 向 element 发送 event |
| `gst_event_new_step()` | 创建 step event，用于逐帧推进 |
| `GST_FORMAT_BUFFERS` | step 单位为 buffer 数量 |
| `video-sink` 属性 | 从 `playbin` 取出实际视频 sink |

## 这篇教程的核心思想

播放速度不是普通属性，而是通过 event 告诉 pipeline：

- 改变 rate 时，创建 seek event。
- 正向播放时，segment 是 `[当前位置, 结尾]`。
- 反向播放时，segment 是 `[0, 当前位置]`，方向由负 rate 表示。
- event 最好发给 `playbin` 内部的某个实际 sink，避免多个 sink 重复 seek。
- 逐帧播放用 step event，通常配合暂停状态使用。

理解这套机制后，就能给播放器增加常见控制能力：倍速播放、慢动作、倒放、单帧前进，以及更复杂的 trick mode UI。

## 可尝试的改动

- 把默认 URI 改成本地文件，比较本地和网络流的变速支持差异。
- 增加一个按键，把 rate 直接重置为 `1.0`。
- 把 `GST_SEEK_FLAG_ACCURATE` 换成 `GST_SEEK_FLAG_KEY_UNIT`，比较响应速度和位置精度。
- 在 `send_seek_event()` 后检查 `gst_element_send_event()` 的返回值。
- 增加当前 position/duration 打印，观察倒放时 position 如何变化。
- 尝试向 `audio-sink` 发送 event，比较和 `video-sink` 的行为差异。

