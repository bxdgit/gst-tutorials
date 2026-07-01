# Basic Tutorial 8: Short-cutting the Pipeline 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-8.c](../../src/basic-tutorial/basic-tutorial-8.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/short-cutting-the-pipeline.html?gi-language=c>

这个 demo 的主题是 **短接管线**：应用程序不只是让 GStreamer 自己从 source 读数据、自己把数据送到 sink，而是主动参与数据流。

具体来说，它演示了两个 element：

- `appsrc`：应用程序自己生成数据，然后注入到 GStreamer 管线中。
- `appsink`：GStreamer 管线中的数据流到这里后，再被应用程序取出来处理。

官方教程的核心目标就是说明：GStreamer pipeline 不一定是完全封闭的。应用程序可以在任意位置把外部数据注入进去，也可以把内部流动的数据拿出来。

## 这个 Demo 做了什么

这个 demo 扩展了 Basic Tutorial 7 的管线。第 7 篇使用 `audiotestsrc` 生成测试音频；第 8 篇把它换成 `appsrc`，由应用程序自己生成音频 sample。

管线结构如下：

```text
            -> queue -> audioconvert -> audioresample -> autoaudiosink
appsrc -> tee
            -> queue -> audioconvert -> wavescope -> videoconvert -> autovideosink
            -> queue -> appsink
```

三条分支分别做三件事：

- 音频分支：播放应用程序生成的声音。
- 视频分支：把音频信号变成波形视频显示出来。
- 应用分支：把同一份音频数据送到 `appsink`，再由应用层取出。demo 里只是打印 `*` 表示收到一个 sample。

运行时通常会：

- 听到一个频率变化的声音。
- 看到一个波形视频窗口。
- 终端不断打印 `*`，表示 `appsink` 持续收到数据。

## CustomData 数据结构

```c
typedef struct _CustomData {
  GstElement *pipeline, *app_source, *tee, *audio_queue, *audio_convert1,
      *audio_resample, *audio_sink;
  GstElement *video_queue, *audio_convert2, *visual, *video_convert,
      *video_sink;
  GstElement *app_queue, *app_sink;

  guint64 num_samples;
  gfloat a, b, c, d;

  guint sourceid;

  GMainLoop *main_loop;
} CustomData;
```

字段含义如下：

| 字段 | 作用 |
| --- | --- |
| `pipeline` | 整个 GStreamer 管线 |
| `app_source` | `appsrc`，应用程序向管线注入音频数据 |
| `tee` | 把音频流复制成三路 |
| `audio_*` | 音频播放分支 |
| `video_*` | 波形可视化分支 |
| `app_queue` / `app_sink` | 应用取数分支 |
| `num_samples` | 已生成 sample 数，用于计算时间戳 |
| `a, b, c, d` | 生成波形用的内部状态变量 |
| `sourceid` | GLib idle source ID，用于启动或停止喂数据 |
| `main_loop` | GLib 主循环 |

这个 demo 不再只依赖 GStreamer 的 streaming 线程，还会用 GLib main loop 调度 `push_data()`，把应用生成的数据喂给 `appsrc`。

## Buffer 是什么

数据在 GStreamer 管线中以 `GstBuffer` 为单位流动。

一个 buffer 不是固定含义的“一个音频帧”或“一个视频帧”。它只是某一段媒体数据的容器，里面可能包含一个或多个 `GstMemory`。不同 element 可以按自己的方式拆分、合并或转换 buffer。

对这个 demo 来说，每次创建的 buffer 大小固定为：

```c
#define CHUNK_SIZE 1024
```

每个音频 sample 是 16 bit，也就是 2 字节，所以每个 buffer 里有：

```c
gint num_samples = CHUNK_SIZE / 2;
```

也就是 512 个 mono 16-bit sample。

## 音频格式和 Caps

demo 定义采样率：

```c
#define SAMPLE_RATE 44100
```

然后用 `GstAudioInfo` 构造音频 caps：

```c
gst_audio_info_set_format (&info, GST_AUDIO_FORMAT_S16,
    SAMPLE_RATE, 1, NULL);
audio_caps = gst_audio_info_to_caps (&info);
```

这表示应用程序生成的数据格式是：

```text
audio/x-raw
format = S16
rate = 44100
channels = 1
```

`appsrc` 必须告诉下游自己会产生什么格式的数据，否则 GStreamer 不知道下游 element 能不能理解这些 buffer。

## 配置 appsrc

```c
g_object_set (data.app_source,
    "caps", audio_caps,
    "format", GST_FORMAT_TIME,
    NULL);
```

两个属性很关键：

| 属性 | 作用 |
| --- | --- |
| `caps` | 告诉下游 `appsrc` 输出的媒体格式 |
| `format` | 告诉 `appsrc` 时间相关信息使用 `GST_FORMAT_TIME` |

然后连接两个信号：

```c
g_signal_connect (data.app_source, "need-data",
    G_CALLBACK (start_feed), &data);
g_signal_connect (data.app_source, "enough-data",
    G_CALLBACK (stop_feed), &data);
```

`appsrc` 内部有队列。它通过信号告诉应用程序什么时候该继续喂数据，什么时候该停一下：

| 信号 | 含义 |
| --- | --- |
| `need-data` | `appsrc` 快没数据了，应用应该开始 push buffer |
| `enough-data` | `appsrc` 已经有足够数据，应用应该暂停 push |

这个 demo 使用的是一种比较方便的 push 模式：应用不一直盲目推数据，而是根据 `appsrc` 的背压信号动态启动和停止数据生成。

## start_feed：开始喂数据

```c
static void start_feed (GstElement *source, guint size,
    CustomData *data) {
  if (data->sourceid == 0) {
    g_print ("Start feeding\n");
    data->sourceid = g_idle_add ((GSourceFunc) push_data, data);
  }
}
```

当 `appsrc` 发出 `need-data` 时，程序通过 `g_idle_add()` 注册一个 idle handler。

GLib idle handler 的意思是：当 main loop 没有更高优先级任务要处理时，就调用这个函数。这里被调用的函数是：

```c
push_data()
```

`sourceid` 用来记录这个 idle source，后面 `stop_feed()` 会用它移除 idle handler，避免继续推数据。

## stop_feed：停止喂数据

```c
static void stop_feed (GstElement *source, CustomData *data) {
  if (data->sourceid != 0) {
    g_print ("Stop feeding\n");
    g_source_remove (data->sourceid);
    data->sourceid = 0;
  }
}
```

当 `appsrc` 发出 `enough-data` 时，说明内部队列已经够满了。此时程序移除 idle handler，停止继续 push buffer。

这就是一个简单的流控机制：

```text
need-data   -> g_idle_add(push_data)  -> 开始产生 buffer
enough-data -> g_source_remove(...)   -> 暂停产生 buffer
```

## push_data：生成 GstBuffer 并推入 appsrc

`push_data()` 是这个 demo 最重要的函数。它完成四件事：

1. 分配一个新的 `GstBuffer`。
2. 设置 buffer 的时间戳和 duration。
3. 写入应用自己生成的音频数据。
4. 通过 `push-buffer` 信号把 buffer 送进 `appsrc`。

### 创建 Buffer

```c
buffer = gst_buffer_new_and_alloc (CHUNK_SIZE);
```

这会创建一个大小为 1024 字节的新 buffer。

### 设置时间戳和时长

```c
GST_BUFFER_TIMESTAMP (buffer) =
    gst_util_uint64_scale (data->num_samples, GST_SECOND, SAMPLE_RATE);
GST_BUFFER_DURATION (buffer) =
    gst_util_uint64_scale (num_samples, GST_SECOND, SAMPLE_RATE);
```

这里使用 `num_samples` 计算时间，因为音频的时间轴可以通过采样率换算：

```text
时间 = sample 数 / sample rate
```

`gst_util_uint64_scale()` 用整数方式做比例换算，避免手写浮点计算导致精度问题。

对 44100 Hz、512 samples 来说，一个 buffer 的 duration 大约是：

```text
512 / 44100 秒 ≈ 11.6 ms
```

时间戳很重要。GStreamer 根据 buffer timestamp 和 duration 决定何时播放、同步、渲染这些数据。

### 写入音频数据

```c
gst_buffer_map (buffer, &map, GST_MAP_WRITE);
raw = (gint16 *)map.data;
```

`gst_buffer_map()` 把 buffer 的内存映射出来，应用就可以直接写入 sample。

然后生成波形：

```c
data->c += data->d;
data->d -= data->c / 1000;
freq = 1100 + 1000 * data->d;
for (i = 0; i < num_samples; i++) {
  data->a += data->b;
  data->b -= data->a / freq;
  raw[i] = (gint16)(500 * data->a);
}
```

这段不是 GStreamer 的核心 API，而是一个简陋的波形生成器。它不断更新 `a, b, c, d` 这些状态变量，产生一个频率会变化的音频信号。

写完后解除映射：

```c
gst_buffer_unmap (buffer, &map);
data->num_samples += num_samples;
```

### 推入 appsrc

```c
g_signal_emit_by_name (data->app_source,
    "push-buffer", buffer, &ret);
```

`push-buffer` 是 `appsrc` 的 action signal。应用通过它把一个 `GstBuffer` 送进 GStreamer 管线。

推完以后释放当前引用：

```c
gst_buffer_unref (buffer);
```

如果 push 失败：

```c
if (ret != GST_FLOW_OK) {
  return FALSE;
}
```

返回 `FALSE` 会让 GLib 移除这个 idle handler，停止继续调用 `push_data()`。

## 配置 appsink

```c
g_object_set (data.app_sink,
    "emit-signals", TRUE,
    "caps", audio_caps,
    NULL);
g_signal_connect (data.app_sink, "new-sample",
    G_CALLBACK (new_sample), &data);
```

`appsink` 默认不会为每个 sample 发信号，因为那样有额外开销。要使用 `new-sample` 回调，必须设置：

```c
"emit-signals", TRUE
```

`caps` 属性表示 `appsink` 希望接收的数据格式。这里和 `appsrc` 使用同一份 `audio_caps`，也就是 mono 16-bit 44100 Hz 原始音频。

设置完后释放 caps 引用：

```c
gst_caps_unref (audio_caps);
```

## new_sample：从 appsink 取数据

```c
static GstFlowReturn new_sample (GstElement *sink, CustomData *data) {
  GstSample *sample;

  g_signal_emit_by_name (sink, "pull-sample", &sample);
  if (sample) {
    g_print ("*");
    gst_sample_unref (sample);
    return GST_FLOW_OK;
  }

  return GST_FLOW_FLUSHING;
}
```

当 `appsink` 收到一个新的 sample，会发出 `new-sample` 信号。回调里通过 `pull-sample` 取出 `GstSample`。

`GstSample` 通常包含：

- 一个 `GstBuffer`
- 这份 buffer 对应的 caps
- segment 信息
- 其他上下文信息

这个 demo 只是打印一个 `*`，表示应用成功从管线里拿到数据。真实项目里，可以在这里做更多事情，例如：

- 分析音频能量。
- 写文件。
- 发送到网络。
- 交给机器学习模型处理。
- 做自定义可视化或监控。

处理完 sample 后必须释放：

```c
gst_sample_unref (sample);
```

## 创建三分支管线

这篇继续使用第 7 篇的 `tee + queue` 模式，只是分支更多。

创建 element：

```c
data.app_source = gst_element_factory_make ("appsrc", "audio_source");
data.tee = gst_element_factory_make ("tee", "tee");
data.audio_queue = gst_element_factory_make ("queue", "audio_queue");
data.audio_convert1 = gst_element_factory_make ("audioconvert", "audio_convert1");
data.audio_resample = gst_element_factory_make ("audioresample", "audio_resample");
data.audio_sink = gst_element_factory_make ("autoaudiosink", "audio_sink");
data.video_queue = gst_element_factory_make ("queue", "video_queue");
data.audio_convert2 = gst_element_factory_make ("audioconvert", "audio_convert2");
data.visual = gst_element_factory_make ("wavescope", "visual");
data.video_convert = gst_element_factory_make ("videoconvert", "video_convert");
data.video_sink = gst_element_factory_make ("autovideosink", "video_sink");
data.app_queue = gst_element_factory_make ("queue", "app_queue");
data.app_sink = gst_element_factory_make ("appsink", "app_sink");
```

各分支作用：

| 分支 | 链路 | 作用 |
| --- | --- | --- |
| 音频播放 | `queue -> audioconvert -> audioresample -> autoaudiosink` | 播放声音 |
| 视频波形 | `queue -> audioconvert -> wavescope -> videoconvert -> autovideosink` | 显示波形 |
| 应用取数 | `queue -> appsink` | 把数据交回应用程序 |

每个分支前都有一个 `queue`，这样三条分支可以在独立线程中推进，避免一个分支阻塞其他分支。

## 连接 Always Pad 部分

```c
gst_element_link_many (data.app_source, data.tee, NULL)
gst_element_link_many (data.audio_queue, data.audio_convert1,
    data.audio_resample, data.audio_sink, NULL)
gst_element_link_many (data.video_queue, data.audio_convert2,
    data.visual, data.video_convert, data.video_sink, NULL)
gst_element_link_many (data.app_queue, data.app_sink, NULL)
```

这些链路可以直接连接，因为它们使用的是已经存在的 always pad。

注意：`tee` 到三个 queue 的连接仍然不能直接自动完成，因为 `tee` 的 source pad 是 request pad。

## 手动连接 tee 的 Request Pad

```c
tee_audio_pad = gst_element_request_pad_simple (data.tee, "src_%u");
queue_audio_pad = gst_element_get_static_pad (data.audio_queue, "sink");

tee_video_pad = gst_element_request_pad_simple (data.tee, "src_%u");
queue_video_pad = gst_element_get_static_pad (data.video_queue, "sink");

tee_app_pad = gst_element_request_pad_simple (data.tee, "src_%u");
queue_app_pad = gst_element_get_static_pad (data.app_queue, "sink");
```

然后手动连接：

```c
gst_pad_link (tee_audio_pad, queue_audio_pad)
gst_pad_link (tee_video_pad, queue_video_pad)
gst_pad_link (tee_app_pad, queue_app_pad)
```

三个 request pad 分别对应三条分支：

```text
tee:src_0 -> audio_queue:sink
tee:src_1 -> video_queue:sink
tee:src_2 -> app_queue:sink
```

实际编号由 GStreamer 分配，不能在代码里假设一定是这些名字。

连接后释放 queue pad 引用：

```c
gst_object_unref (queue_audio_pad);
gst_object_unref (queue_video_pad);
gst_object_unref (queue_app_pad);
```

request pad 会在退出时专门释放。

## Bus 和 Main Loop

这个 demo 使用 bus signal watch：

```c
bus = gst_element_get_bus (data.pipeline);
gst_bus_add_signal_watch (bus);
g_signal_connect (G_OBJECT (bus), "message::error",
    (GCallback)error_cb, &data);
gst_object_unref (bus);
```

这里只处理错误消息。发生错误时：

```c
g_main_loop_quit (data->main_loop);
```

随后启动 pipeline：

```c
gst_element_set_state (data.pipeline, GST_STATE_PLAYING);
```

再创建并运行 GLib 主循环：

```c
data.main_loop = g_main_loop_new (NULL, FALSE);
g_main_loop_run (data.main_loop);
```

GLib main loop 对这个 demo 很重要，因为：

- bus signal watch 需要 main loop 分发消息。
- `g_idle_add()` 注册的 `push_data()` 也需要 main loop 调度。
- `appsrc` 的 `need-data/enough-data` 流控也依赖这套事件驱动逻辑来启动和停止喂数据。

## 释放 Request Pad 和资源

退出主循环后，释放 `tee` 的三个 request pad：

```c
gst_element_release_request_pad (data.tee, tee_audio_pad);
gst_element_release_request_pad (data.tee, tee_video_pad);
gst_element_release_request_pad (data.tee, tee_app_pad);
gst_object_unref (tee_audio_pad);
gst_object_unref (tee_video_pad);
gst_object_unref (tee_app_pad);
```

然后停止并释放 pipeline：

```c
gst_element_set_state (data.pipeline, GST_STATE_NULL);
gst_object_unref (data.pipeline);
```

和第 7 篇一样，request pad 的清理分两步：

1. `gst_element_release_request_pad()`：归还给 `tee`。
2. `gst_object_unref()`：释放当前代码持有的引用。

## 运行时可能看到什么

启动后通常会打印类似：

```text
Obtained request pad src_0 for audio branch.
Obtained request pad src_1 for video branch.
Obtained request pad src_2 for app branch.
Start feeding
****************************
```

同时你会听到频率变化的声音，并看到波形窗口。`*` 的数量表示 `appsink` 收到了多少 sample。

这个 demo 的 source 是应用自己生成的，默认不会自然结束，所以通常需要用户手动中断程序，或者代码遇到错误后通过 `error_cb()` 退出 main loop。

## 关键 API 总结

| API / Element | 作用 |
| --- | --- |
| `appsrc` | 应用向 GStreamer 管线注入数据 |
| `appsink` | 应用从 GStreamer 管线取出数据 |
| `GstBuffer` | 管线中传递的数据块 |
| `GstSample` | appsink 取出的样本，通常包含 buffer 和 caps |
| `gst_buffer_new_and_alloc()` | 分配新 buffer |
| `gst_buffer_map()` / `gst_buffer_unmap()` | 映射 buffer 内存以读写数据 |
| `GST_BUFFER_TIMESTAMP` | 设置 buffer 时间戳 |
| `GST_BUFFER_DURATION` | 设置 buffer 时长 |
| `gst_util_uint64_scale()` | 用整数比例安全换算时间 |
| `gst_audio_info_set_format()` | 构造音频格式描述 |
| `gst_audio_info_to_caps()` | 把 `GstAudioInfo` 转成 caps |
| `need-data` | `appsrc` 需要更多数据时发出的信号 |
| `enough-data` | `appsrc` 数据足够时发出的信号 |
| `push-buffer` | 向 `appsrc` 推入 buffer 的 action signal |
| `emit-signals` | 让 `appsink` 发出 `new-sample` 等信号 |
| `new-sample` | `appsink` 收到新 sample 时发出的信号 |
| `pull-sample` | 从 `appsink` 拉取 sample 的 action signal |
| `g_idle_add()` | 在 GLib main loop 空闲时调度函数 |
| `g_source_remove()` | 移除 GLib source |
| `tee` | 把一份数据复制到多个分支 |
| `queue` | 为每个分支创建线程边界 |

## 这篇教程的核心思想

这个 demo 展示了应用和 GStreamer 管线双向交互：

- `appsrc` 让应用程序变成一个 source。
- `appsink` 让应用程序变成一个 sink。
- `GstBuffer` 是应用和管线交换媒体数据的基本单位。
- caps 和 timestamp 必须正确设置，下游才能理解并同步这些数据。
- `need-data` / `enough-data` 是一种简单的流控方式，避免应用无节制地推数据。

理解这套模式后，就可以把 GStreamer 接到很多外部系统上：实时采集设备、网络协议、自定义解码器、AI 处理模块、音视频分析算法、文件封装器等。

## 可尝试的改动

- 在 `new_sample()` 中取出 `GstBuffer` 并计算音频峰值或 RMS。
- 调整 `CHUNK_SIZE`，观察 `appsink` 打印 `*` 的频率变化。
- 修改 `SAMPLE_RATE` 或 channels，观察 caps 和播放效果。
- 把 `appsink` 分支中的数据写入文件。
- 给 `appsrc` 发送 EOS，让程序自然结束。
- 改用 `gstreamer-app-1.0` 提供的 `gst_app_src_push_buffer()` / `gst_app_sink_pull_sample()` API，而不是通过信号调用。

