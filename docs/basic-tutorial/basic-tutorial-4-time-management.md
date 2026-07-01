# Basic Tutorial 4: Time Management 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-4.c](../../src/basic-tutorial/basic-tutorial-4.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/time-management.html?gi-language=c>

这个 demo 的主题是 **时间管理**：应用程序如何周期性查询当前播放位置、查询媒体总时长、判断当前媒体是否支持 seek，并在播放到指定时间后跳转到另一个时间点。

## 这个 Demo 做了什么

程序使用 `playbin` 播放远程 WebM 文件：

```text
https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

运行后它会：

- 启动播放音视频。
- 每 100ms 查询一次当前播放位置。
- 在不知道总时长时查询媒体 duration。
- 打印 `当前位置 / 总时长`。
- 当播放超过 10 秒后，自动 seek 到 30 秒位置。
- 监听 `ERROR`、`EOS`、`DURATION`、`STATE_CHANGED` 等 bus 消息。

可以把它想成一个非常简化的播放器内核：它没有真正的图形界面，但已经具备播放器进度条常见的核心能力。

## 管线结构

这个 demo 只显式创建了一个 element：

```c
data.playbin = gst_element_factory_make ("playbin", "playbin");
```

`playbin` 是 GStreamer 提供的高级播放器 element。它内部会自动完成 URI 读取、解复用、解码、音视频转换和输出选择。也就是说，虽然代码里只有一个 element，但 `playbin` 内部其实帮我们搭好了复杂的播放管线。

因此这个 demo 不关注手动 link element，而是关注：

```text
应用程序 <-> playbin
```

应用层不断向 `playbin` 查询时间信息，并在合适的时候发起 seek。

## CustomData 数据结构

```c
typedef struct _CustomData
{
  GstElement *playbin;
  gboolean playing;
  gboolean terminate;
  gboolean seek_enabled;
  gboolean seek_done;
  gint64 duration;
} CustomData;
```

各字段作用如下：

| 字段 | 作用 |
| --- | --- |
| `playbin` | 唯一显式创建的播放 element |
| `playing` | 当前 pipeline 是否处于 `PLAYING` 状态 |
| `terminate` | 主循环是否应该退出 |
| `seek_enabled` | 当前媒体是否支持 seek |
| `seek_done` | 是否已经执行过本 demo 的自动 seek |
| `duration` | 媒体总时长，单位是纳秒 |

初始化时：

```c
data.playing = FALSE;
data.terminate = FALSE;
data.seek_enabled = FALSE;
data.seek_done = FALSE;
data.duration = GST_CLOCK_TIME_NONE;
```

`GST_CLOCK_TIME_NONE` 表示当前还不知道有效时长。后面如果收到 `GST_MESSAGE_DURATION`，程序也会把 `duration` 重置成这个值，表示需要重新查询。

## 初始化与启动播放

和前几个教程一样，程序先初始化 GStreamer：

```c
gst_init (&argc, &argv);
```

然后创建 `playbin` 并设置 URI：

```c
g_object_set (data.playbin, "uri",
    "https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm",
    NULL);
```

最后启动播放：

```c
ret = gst_element_set_state (data.playbin, GST_STATE_PLAYING);
```

如果状态切换失败，说明播放管线无法进入运行状态，程序释放 `playbin` 后退出。

## 带超时的 Bus 等待

这是本教程和前面教程最关键的区别之一：

```c
msg = gst_bus_timed_pop_filtered (bus, 100 * GST_MSECOND,
    GST_MESSAGE_STATE_CHANGED | GST_MESSAGE_ERROR | GST_MESSAGE_EOS |
    GST_MESSAGE_DURATION);
```

之前的教程通常使用 `GST_CLOCK_TIME_NONE` 作为超时时间，表示一直阻塞，直到收到消息。

这里改成了：

```c
100 * GST_MSECOND
```

意思是最多等待 100ms：

- 如果 100ms 内收到消息，就处理消息。
- 如果 100ms 内没有消息，函数返回 `NULL`。

这个 `NULL` 并不是错误，而是一个定时器机会。程序利用它周期性刷新播放位置，类似播放器 UI 每隔一小段时间更新进度条。

GStreamer 的时间单位是纳秒，所以代码使用 `GST_MSECOND`、`GST_SECOND` 这样的宏来表达时间，既准确又可读。

## 周期性查询当前位置

当 `msg == NULL`，表示本轮等待超时。如果当前正在播放：

```c
if (data.playing) {
  gint64 current = -1;
```

程序查询当前播放位置：

```c
gst_element_query_position (data.playbin, GST_FORMAT_TIME, &current)
```

参数含义：

| 参数 | 含义 |
| --- | --- |
| `data.playbin` | 查询目标 |
| `GST_FORMAT_TIME` | 用时间格式查询 |
| `&current` | 输出当前播放位置 |

`current` 的单位是纳秒。`GST_FORMAT_TIME` 表示我们关心的是时间轴位置，而不是字节数、buffer 数量等其他格式。

## 查询媒体总时长

总时长不需要每 100ms 都查一次，所以 demo 做了缓存：

```c
if (!GST_CLOCK_TIME_IS_VALID (data.duration)) {
  gst_element_query_duration (data.playbin, GST_FORMAT_TIME,
      &data.duration);
}
```

只有当 `data.duration` 无效时，才调用 `gst_element_query_duration()`。

这有两个好处：

- 避免重复查询。
- 当媒体时长发生变化时，可以通过 `GST_MESSAGE_DURATION` 把缓存作废，下一轮再重新查询。

## 打印时间

```c
g_print ("Position %" GST_TIME_FORMAT " / %" GST_TIME_FORMAT "\r",
    GST_TIME_ARGS (current), GST_TIME_ARGS (data.duration));
```

`current` 和 `duration` 都是纳秒整数，直接打印不适合阅读。GStreamer 提供了两个宏：

| 宏 | 作用 |
| --- | --- |
| `GST_TIME_FORMAT` | 时间格式化字符串 |
| `GST_TIME_ARGS()` | 把纳秒时间拆成时、分、秒、纳秒等参数 |

输出通常类似：

```text
Position 0:00:04.123456789 / 0:00:52.250000000
```

末尾的 `\r` 是回车符，不是换行。它会让下一次输出覆盖当前行，从而形成类似进度条刷新的效果。

## 自动 Seek

当播放超过 10 秒，并且当前媒体支持 seek，且之前还没有 seek 过，程序会跳到 30 秒：

```c
if (data.seek_enabled && !data.seek_done && current > 10 * GST_SECOND) {
  g_print ("\nReached 10s, performing seek...\n");
  gst_element_seek_simple (data.playbin, GST_FORMAT_TIME,
      GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT, 30 * GST_SECOND);
  data.seek_done = TRUE;
}
```

这里使用的是简化版 seek API：

```c
gst_element_seek_simple()
```

参数含义：

| 参数 | 含义 |
| --- | --- |
| `data.playbin` | 要 seek 的目标 |
| `GST_FORMAT_TIME` | seek 位置使用时间单位 |
| `GST_SEEK_FLAG_FLUSH \| GST_SEEK_FLAG_KEY_UNIT` | seek 行为标志 |
| `30 * GST_SECOND` | 目标位置：30 秒 |

两个 seek flag 很重要：

| Flag | 作用 |
| --- | --- |
| `GST_SEEK_FLAG_FLUSH` | 丢弃管线中旧位置的数据，让 seek 响应更快 |
| `GST_SEEK_FLAG_KEY_UNIT` | 跳到接近目标位置的关键帧，视频 seek 更容易立刻显示 |

如果不使用 `FLUSH`，旧数据可能还会继续从 pipeline 中流出来，用户会感觉 seek 不够及时。

如果不使用 `KEY_UNIT`，GStreamer 可能需要从最近关键帧解码到目标时间点，画面出现可能更慢，但时间位置可能更精确。

## handle_message 消息处理

主循环收到 bus 消息后，交给：

```c
handle_message (&data, msg);
```

这个函数集中处理四类消息。

### ERROR

```c
gst_message_parse_error (msg, &err, &debug_info);
```

出现错误时，程序打印错误来源、错误信息和调试信息，然后设置：

```c
data->terminate = TRUE;
```

主循环会退出。

### EOS

```c
g_print ("\nEnd-Of-Stream reached.\n");
data->terminate = TRUE;
```

`EOS` 表示 End Of Stream，也就是媒体播放结束。收到后退出主循环。

### DURATION

```c
data->duration = GST_CLOCK_TIME_NONE;
```

`GST_MESSAGE_DURATION` 表示媒体总时长发生变化。程序不会在消息处理函数里立刻查询时长，而是把缓存标记为无效。下一次 UI 刷新时，会重新调用 `gst_element_query_duration()`。

这种写法很常见：消息只负责标记状态，实际查询放到统一的刷新逻辑中完成。

### STATE_CHANGED

```c
gst_message_parse_state_changed (msg, &old_state, &new_state,
    &pending_state);
```

状态变化消息可能来自 pipeline 内部很多 element。demo 只关心 `playbin` 自己的状态变化：

```c
if (GST_MESSAGE_SRC (msg) == GST_OBJECT (data->playbin)) {
```

当 `playbin` 进入 `PLAYING` 状态时：

```c
data->playing = (new_state == GST_STATE_PLAYING);
```

后面的周期性位置查询会依赖这个标志。教程中特别强调：位置、时长、seek 相关查询通常在 `PAUSED` 或 `PLAYING` 状态下更可靠，因为这时 element 已经拿到了足够的媒体信息。

## 查询是否支持 Seek

进入 `PLAYING` 后，程序创建一个 seeking query：

```c
query = gst_query_new_seeking (GST_FORMAT_TIME);
```

然后把 query 发给 `playbin`：

```c
if (gst_element_query (data->playbin, query)) {
```

再解析结果：

```c
gst_query_parse_seeking (query, NULL, &data->seek_enabled, &start, &end);
```

解析结果里包含：

| 输出 | 含义 |
| --- | --- |
| `seek_enabled` | 是否允许 seek |
| `start` | 可 seek 范围起点 |
| `end` | 可 seek 范围终点 |

不是所有媒体都支持 seek。例如直播流通常不能随意跳转；本地文件或支持范围请求的网络媒体通常可以 seek。

用完 query 后释放：

```c
gst_query_unref (query);
```

## 程序运行时的大致输出

实际输出会随 GStreamer 版本、网络情况和媒体状态略有不同，通常类似：

```text
Pipeline state changed from NULL to READY:
Pipeline state changed from READY to PAUSED:
Pipeline state changed from PAUSED to PLAYING:
Seeking is ENABLED from 0:00:00.000000000 to 0:00:52.250000000
Position 0:00:09.934000000 / 0:00:52.250000000
Reached 10s, performing seek...
Position 0:00:30.120000000 / 0:00:52.250000000
...
End-Of-Stream reached.
```

因为 `g_print()` 使用 `\r` 覆盖同一行，终端里看到的进度输出可能不会一行一行保留。

## 资源清理

主循环结束后：

```c
gst_object_unref (bus);
gst_element_set_state (data.playbin, GST_STATE_NULL);
gst_object_unref (data.playbin);
```

清理顺序是：

1. 释放 bus。
2. 把 `playbin` 设置回 `NULL` 状态，停止播放并释放内部资源。
3. 释放 `playbin` 对象。

## 关键 API 总结

| API / 宏 | 作用 |
| --- | --- |
| `playbin` | 高级播放器 element，内部自动构建播放管线 |
| `gst_bus_timed_pop_filtered()` | 等待 bus 消息，可设置超时 |
| `GST_MSECOND` / `GST_SECOND` | 时间单位宏，GStreamer 时间单位为纳秒 |
| `gst_element_query_position()` | 查询当前播放位置 |
| `gst_element_query_duration()` | 查询媒体总时长 |
| `GST_CLOCK_TIME_NONE` | 表示无效或未知时间 |
| `GST_CLOCK_TIME_IS_VALID()` | 判断时间值是否有效 |
| `GST_TIME_FORMAT` | 打印 GStreamer 时间的格式字符串 |
| `GST_TIME_ARGS()` | 把 GStreamer 时间转换为打印参数 |
| `gst_element_seek_simple()` | 执行简化 seek |
| `GST_SEEK_FLAG_FLUSH` | seek 时清空旧数据，提高响应性 |
| `GST_SEEK_FLAG_KEY_UNIT` | seek 到关键帧附近 |
| `gst_query_new_seeking()` | 创建 seeking 能力查询 |
| `gst_element_query()` | 向 element 发出 query |
| `gst_query_parse_seeking()` | 解析 seeking query 结果 |
| `gst_query_unref()` | 释放 query |

## 这篇教程的核心思想

播放器类程序通常不是只等待 `ERROR` 或 `EOS`。它还需要周期性地和 pipeline 交互：

- 查询当前位置，用来更新进度条。
- 查询总时长，用来显示总时间。
- 判断媒体是否支持 seek，用来决定进度条能不能拖动。
- 用户拖动进度条时，对 pipeline 发起 seek。

这个 demo 用 100ms 定时轮询模拟 UI 刷新，并用自动跳转演示 seek。理解它之后，就能把这些逻辑迁移到真实播放器的按钮、进度条和时间显示上。

## 可尝试的改动

- 把自动 seek 的目标从 30 秒改成其他时间点。
- 去掉 `GST_SEEK_FLAG_KEY_UNIT`，观察 seek 后画面出现速度和精确度的变化。
- 把 `100 * GST_MSECOND` 改成 `500 * GST_MSECOND`，观察进度刷新频率。
- 把 URI 换成直播流，观察 `seek_enabled` 是否变为 `FALSE`。
- 增加键盘输入或 UI 控件，让用户手动触发 `gst_element_seek_simple()`。

