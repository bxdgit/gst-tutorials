# Basic Tutorial 7: Multithreading and Pad Availability 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-7.c](../../src/basic-tutorial/basic-tutorial-7.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/multithreading-and-pad-availability.html?gi-language=c>

这个 demo 的主题是 **多线程与 Pad Availability**。它展示了两个非常实用的 GStreamer 概念：

- 用 `queue` 把管线拆成多个执行线程。
- 用 `tee` 复制同一份数据流，并通过 request pad 手动连接多个分支。

最终效果是：程序生成一个测试音频信号，一路送到声卡播放，另一路送到 `wavescope` 生成波形视频并显示到屏幕。

## 这个 Demo 做了什么

管线结构可以写成：

```text
                 -> queue -> audioconvert -> audioresample -> autoaudiosink
audiotestsrc -> tee
                 -> queue -> wavescope -> videoconvert -> autovideosink
```

含义是：

- `audiotestsrc` 生成测试音频。
- `tee` 把同一份音频流复制成两路。
- 音频分支播放声音。
- 视频分支把音频波形转换成视频画面并显示。
- 两个分支前面各有一个 `queue`，让分支在不同线程中运行。

官方教程里也强调：包含多个 sink 的管线通常需要多线程，否则一个 sink 等待同步时可能阻塞整个数据流，导致另一个 sink 没机会继续处理。

## 为什么需要 Queue

`queue` 的作用不只是缓存，它还会创建线程边界。

可以把它理解成：

```text
上游线程把数据推入 queue
下游线程从 queue 取出数据继续处理
```

也就是说，`queue` 的 sink pad 收到数据后，把数据放入队列并返回；另一个线程再从队列中取出数据推给下游。

这个 demo 有两个 queue：

```c
audio_queue = gst_element_factory_make ("queue", "audio_queue");
video_queue = gst_element_factory_make ("queue", "video_queue");
```

因此管线大致会分成三段执行：

```text
主音频源分支：audiotestsrc -> tee
音频输出分支：audio_queue -> audioconvert -> audioresample -> autoaudiosink
视频波形分支：video_queue -> wavescope -> videoconvert -> autovideosink
```

如果没有 queue，两个分支可能互相阻塞。尤其是多 sink 管线中，音频 sink 和视频 sink 都要做时钟同步，一个分支被阻塞时，另一个分支也可能无法推进。

## Pad Availability 回顾

GStreamer 里 pad 的可用性主要有三类：

| 类型 | 含义 | 例子 |
| --- | --- | --- |
| Always Pad | element 创建后 pad 就一直存在 | `audiotestsrc:src`、`queue:sink` |
| Sometimes Pad | 运行时根据数据内容动态出现 | `uridecodebin` 的输出 pad |
| Request Pad | 应用按需请求创建，用完要释放 | `tee` 的 `src_%u` |

前面的 Basic Tutorial 3 重点讲了 Sometimes Pad。这个 demo 重点讲 Request Pad。

## Tee 的作用

`tee` 用来复制数据流。

它有一个 sink pad，用来接收输入数据；它可以有多个 source pad，每个 source pad 输出一份相同的数据。

问题是：`tee` 初始时不会自动创建所有 source pad。因为应用可能需要一个分支、两个分支，也可能需要更多分支。于是 `tee` 把 source pad 设计成 request pad，需要应用主动请求。

这个 demo 请求了两个 source pad：

```text
tee:src_0 -> audio_queue:sink
tee:src_1 -> video_queue:sink
```

实际 pad 名称可能是 `src_0`、`src_1`，也可能因运行情况略有不同，但都匹配 template 名：

```text
src_%u
```

## 创建 Element

源码先创建所有 element：

```c
audio_source = gst_element_factory_make ("audiotestsrc", "audio_source");
tee = gst_element_factory_make ("tee", "tee");
audio_queue = gst_element_factory_make ("queue", "audio_queue");
audio_convert = gst_element_factory_make ("audioconvert", "audio_convert");
audio_resample = gst_element_factory_make ("audioresample", "audio_resample");
audio_sink = gst_element_factory_make ("autoaudiosink", "audio_sink");
video_queue = gst_element_factory_make ("queue", "video_queue");
visual = gst_element_factory_make ("wavescope", "visual");
video_convert = gst_element_factory_make ("videoconvert", "csp");
video_sink = gst_element_factory_make ("autovideosink", "video_sink");
```

各 element 的作用：

| Element | 作用 |
| --- | --- |
| `audiotestsrc` | 生成测试音频 |
| `tee` | 复制输入流到多个输出分支 |
| `queue` | 缓冲并创建线程边界 |
| `audioconvert` | 转换音频格式 |
| `audioresample` | 转换采样率 |
| `autoaudiosink` | 自动选择音频输出 |
| `wavescope` | 把音频信号渲染成波形视频 |
| `videoconvert` | 转换视频格式 |
| `autovideosink` | 自动选择视频输出 |

`audioconvert`、`audioresample`、`videoconvert` 这些转换 element 很常见。它们可以提高管线兼容性，因为真实音频设备、视频设备支持的 caps 可能和上游输出不完全一致。如果格式已经匹配，这些转换 element 通常会以近似 pass-through 的方式工作。

## 配置 Element 属性

```c
g_object_set (audio_source, "freq", 215.0f, NULL);
g_object_set (visual, "shader", 0, "style", 1, NULL);
```

`audiotestsrc` 的 `freq` 属性控制测试音频频率。这里设置成 215 Hz，是为了让波形在窗口里看起来比较稳定。

`wavescope` 的 `shader` 和 `style` 属性控制波形渲染风格。这里选择的配置更适合演示连续波形。

可以用下面命令查看这些 element 支持的属性：

```sh
gst-inspect-1.0 audiotestsrc
gst-inspect-1.0 wavescope
```

## 连接 Always Pad 部分

程序先把所有 element 加入 pipeline：

```c
gst_bin_add_many (GST_BIN (pipeline), audio_source, tee, audio_queue,
    audio_convert, audio_resample, audio_sink, video_queue, visual,
    video_convert, video_sink, NULL);
```

然后连接那些可以直接自动连接的部分：

```c
gst_element_link_many (audio_source, tee, NULL)
gst_element_link_many (audio_queue, audio_convert, audio_resample,
    audio_sink, NULL)
gst_element_link_many (video_queue, visual, video_convert, video_sink, NULL)
```

这些链路上的 pad 都是 Always Pad，所以可以直接用 `gst_element_link_many()`。

注意这里没有直接写：

```text
tee -> audio_queue
tee -> video_queue
```

因为 `tee` 的输出 pad 是 Request Pad，不应该在这里自动连接。

## 为什么不让 gst_element_link_many 自动处理 Tee

官方教程提醒：`gst_element_link_many()` 确实可以在某些情况下帮你请求 request pad。但这会带来一个麻烦：request pad 用完以后需要释放。如果 pad 是自动请求的，应用很容易忘记释放。

所以更清晰的写法是：

```text
手动请求 tee source pad
手动拿到 queue sink pad
手动 gst_pad_link()
结束时手动 release request pad
```

这个 demo 就是按这条路径写的。

## 手动请求 Tee 的 Request Pad

```c
tee_audio_pad = gst_element_request_pad_simple (tee, "src_%u");
g_print ("Obtained request pad %s for audio branch.\n",
    gst_pad_get_name (tee_audio_pad));
```

`src_%u` 是 `tee` 的 source pad template 名。`%u` 表示 GStreamer 会自动分配数字，比如 `src_0`、`src_1`。

然后拿到音频分支 queue 的 sink pad：

```c
queue_audio_pad = gst_element_get_static_pad (audio_queue, "sink");
```

同样方式为视频分支请求第二个 tee source pad：

```c
tee_video_pad = gst_element_request_pad_simple (tee, "src_%u");
queue_video_pad = gst_element_get_static_pad (video_queue, "sink");
```

这里体现了 request pad 和 always pad 的区别：

| Pad | 获取方式 |
| --- | --- |
| `tee:src_%u` | `gst_element_request_pad_simple()` |
| `queue:sink` | `gst_element_get_static_pad()` |

## 用 gst_pad_link 连接具体 Pad

拿到 pad 后，程序手动连接：

```c
if (gst_pad_link (tee_audio_pad, queue_audio_pad) != GST_PAD_LINK_OK ||
    gst_pad_link (tee_video_pad, queue_video_pad) != GST_PAD_LINK_OK) {
  g_printerr ("Tee could not be linked.\n");
  gst_object_unref (pipeline);
  return -1;
}
```

`gst_element_link()` 和 `gst_element_link_many()` 内部最终也是通过 pad 完成连接。这里只是我们已经明确拿到了具体 pad，所以直接用 `gst_pad_link()`。

连接完成后，释放 queue sink pad 引用：

```c
gst_object_unref (queue_audio_pad);
gst_object_unref (queue_video_pad);
```

注意：这里没有立刻释放 `tee_audio_pad` 和 `tee_video_pad`，因为它们是 request pad，后面还需要显式归还给 `tee`。

## 启动 Pipeline

```c
gst_element_set_state (pipeline, GST_STATE_PLAYING);
```

启动后，`audiotestsrc` 开始生成测试音频：

```text
audiotestsrc -> tee
```

`tee` 把数据复制到两路：

```text
音频分支：queue -> audioconvert -> audioresample -> autoaudiosink
视频分支：queue -> wavescope -> videoconvert -> autovideosink
```

程序没有像前几篇一样监听状态变化，只等待错误或 EOS：

```c
msg = gst_bus_timed_pop_filtered (bus, GST_CLOCK_TIME_NONE,
    GST_MESSAGE_ERROR | GST_MESSAGE_EOS);
```

由于 `audiotestsrc` 默认会持续生成数据，这个 demo 通常不会自然 EOS。一般需要用户关闭窗口或中断程序；如果出现错误，则 bus 会收到 `GST_MESSAGE_ERROR`。

## 释放 Request Pad

结束前必须把 request pad 还给 `tee`：

```c
gst_element_release_request_pad (tee, tee_audio_pad);
gst_element_release_request_pad (tee, tee_video_pad);
gst_object_unref (tee_audio_pad);
gst_object_unref (tee_video_pad);
```

这里有两个动作：

1. `gst_element_release_request_pad()`：告诉 `tee` 不再需要这个 request pad。
2. `gst_object_unref()`：释放当前代码持有的 pad 引用。

这和普通静态 pad 不一样。静态 pad 只需要 unref 你拿到的引用；request pad 还要通知 element 释放这个按需创建的 pad。

官方教程还特别提到：在 `PLAYING` 或 `PAUSED` 状态下请求或释放 pad 需要额外谨慎，通常要配合 pad blocking 等机制。本 demo 是在启动前请求 pad，在结束清理时释放 pad，逻辑更简单。

## 资源清理

```c
if (msg != NULL)
  gst_message_unref (msg);
gst_object_unref (bus);
gst_element_set_state (pipeline, GST_STATE_NULL);
gst_object_unref (pipeline);
```

清理顺序是：

1. 如果收到 bus 消息，释放消息。
2. 释放 bus。
3. 把 pipeline 设置回 `NULL` 状态。
4. 释放 pipeline。pipeline 会连带释放内部 element。

## 运行时可能看到什么

程序启动后通常会打印：

```text
Obtained request pad src_0 for audio branch.
Obtained request pad src_1 for video branch.
```

随后：

- 可以听到一个持续的测试音。
- 会打开一个视频窗口显示波形。

官方说明里提到，波形理论上是正弦波，但因为窗口刷新和渲染时序原因，看起来不一定完全稳定。

## 关键 API 总结

| API / Element | 作用 |
| --- | --- |
| `queue` | 创建线程边界，并提供缓冲 |
| `tee` | 把一份输入流复制到多个输出分支 |
| `wavescope` | 把音频信号可视化成视频波形 |
| `gst_element_request_pad_simple()` | 按 pad template 名请求 request pad |
| `gst_element_get_static_pad()` | 获取 always pad 等静态 pad |
| `gst_pad_link()` | 手动连接两个具体 pad |
| `gst_element_release_request_pad()` | 把 request pad 归还给 element |
| `gst_object_unref()` | 释放当前持有的对象引用 |
| `gst_element_link_many()` | 自动连接常规链路 |
| `gst_bus_timed_pop_filtered()` | 等待指定类型 bus 消息 |

## 这篇教程的核心思想

这个 demo 把两个常用模式组合起来：

- 用 `tee` 做一进多出，让同一份媒体流进入多个处理分支。
- 用 `queue` 给每个分支创建独立线程，避免多 sink 或耗时分支互相阻塞。

同时，它补齐了 pad availability 的第三类：Request Pad。理解 Always、Sometimes、Request 这三类 pad 后，就能读懂很多复杂 GStreamer 管线的连接逻辑。

## 可尝试的改动

- 去掉其中一个 `queue`，观察管线是否更容易卡住或同步异常。
- 再从 `tee` 请求第三个 source pad，增加一个新的处理分支。
- 把 `wavescope` 换成其他可视化 element，例如 `goom`，观察效果变化。
- 修改 `audiotestsrc` 的 `freq` 属性，观察声音和波形变化。
- 用 `gst-inspect-1.0 tee` 查看 `tee` 的 pad template，确认 `src_%u` 是 request pad。

