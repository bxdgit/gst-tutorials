# Basic Tutorial 3: Dynamic Pipelines 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-3.c](../../src/basic-tutorial/basic-tutorial-3.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/dynamic-pipelines.html?gi-language=c>

这个 demo 的主题是 **动态管线**：有些 element 在创建时并不知道自己会输出什么 pad，只有运行起来、解析到真实媒体流以后，才会动态创建 pad。程序需要监听这些 pad 的出现，再决定是否把它们接入后续管线。

## 这个 Demo 做了什么

程序播放一个远程 WebM 文件中的音频流：

```text
https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

它构建的目标音频管线是：

```text
uridecodebin --动态 pad--> audioconvert -> audioresample -> autoaudiosink
```

其中：

- `uridecodebin`：根据 URI 自动下载、解析、解复用、解码媒体，输出解码后的原始音视频数据。
- `audioconvert`：转换音频采样格式、通道布局等。
- `audioresample`：转换音频采样率。
- `autoaudiosink`：自动选择系统可用的音频输出设备。

关键点是：`uridecodebin` 的输出 pad 是 **动态生成** 的，所以程序不能在初始化阶段直接把它 link 到 `audioconvert`。必须等 `uridecodebin` 发出 `pad-added` 信号后，再在回调函数里完成连接。

## 数据结构

```c
typedef struct _CustomData
{
  GstElement *pipeline;
  GstElement *source;
  GstElement *convert;
  GstElement *resample;
  GstElement *sink;
} CustomData;
```

`CustomData` 用来保存整个 demo 会用到的 element 指针。因为 `pad-added` 回调发生在后面，回调函数需要访问 `audioconvert` 等对象，所以程序把这些指针集中放在结构体里，再通过 `g_signal_connect()` 传给回调。

## 初始化 GStreamer

```c
gst_init (&argc, &argv);
```

所有 GStreamer 程序通常都要先调用 `gst_init()`。它会初始化 GStreamer 库，也会解析并移除 GStreamer 自己支持的命令行参数。

## 创建 Element

```c
data.source = gst_element_factory_make ("uridecodebin", "source");
data.convert = gst_element_factory_make ("audioconvert", "convert");
data.resample = gst_element_factory_make ("audioresample", "resample");
data.sink = gst_element_factory_make ("autoaudiosink", "sink");
```

`gst_element_factory_make()` 根据插件工厂名创建 element。第二个参数是 element 在管线中的名字，方便调试和打印。

这里创建了 4 个 element：

| Element | 作用 |
| --- | --- |
| `uridecodebin` | 从 URI 读取媒体并自动解码 |
| `audioconvert` | 转换原始音频格式 |
| `audioresample` | 转换采样率 |
| `autoaudiosink` | 自动选择音频输出 |

随后创建空管线：

```c
data.pipeline = gst_pipeline_new ("test-pipeline");
```

`GstPipeline` 是一个特殊的 `GstBin`，可以容纳多个 element，并统一管理状态、时钟和消息总线。

## 组装静态部分

```c
gst_bin_add_many (GST_BIN (data.pipeline), data.source, data.convert,
    data.resample, data.sink, NULL);
```

这一步只是把 element 加入 pipeline，还没有完成所有连接。

接着程序只连接后半段：

```c
gst_element_link_many (data.convert, data.resample, data.sink, NULL)
```

也就是：

```text
audioconvert -> audioresample -> autoaudiosink
```

注意：这里没有连接 `source -> convert`。原因是 `uridecodebin` 在此时还没有 source pad。它只有在进入运行状态并识别出媒体流以后，才会创建新的输出 pad。

## 设置 URI

```c
g_object_set (data.source, "uri",
    "https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm",
    NULL);
```

`g_object_set()` 用来设置 GObject 属性。`uridecodebin` 的 `uri` 属性指定要播放的媒体地址。

## 监听动态 Pad

```c
g_signal_connect (data.source, "pad-added", G_CALLBACK (pad_added_handler),
    &data);
```

这是整个 demo 最重要的一行。

`uridecodebin` 解析媒体后，可能发现多个流，例如视频流、音频流、字幕流。每发现一个可以输出的流，它就会创建一个新的 source pad，并发出 `pad-added` 信号。

程序注册 `pad_added_handler()`，当新 pad 出现时检查它是不是原始音频。如果是，就把这个新 pad 连接到 `audioconvert` 的 sink pad。

## 启动播放

```c
ret = gst_element_set_state (data.pipeline, GST_STATE_PLAYING);
```

把 pipeline 设置为 `PLAYING` 后，整个管线开始工作。此时 `uridecodebin` 才会真正开始读取 URI、解析容器、解码数据，并动态创建 pad。

如果状态切换失败，程序释放 pipeline 并退出。

## Bus 消息循环

```c
bus = gst_element_get_bus (data.pipeline);
```

GStreamer 中，element 会通过 bus 向应用层发送消息。这个 demo 关注三类消息：

```c
GST_MESSAGE_STATE_CHANGED | GST_MESSAGE_ERROR | GST_MESSAGE_EOS
```

### ERROR

```c
gst_message_parse_error (msg, &err, &debug_info);
```

如果发生错误，程序打印出错 element、错误信息和调试信息，然后结束循环。

### EOS

```c
g_print ("End-Of-Stream reached.\n");
```

`EOS` 是 End Of Stream，表示媒体播放结束。收到后程序退出主循环。

### STATE_CHANGED

```c
if (GST_MESSAGE_SRC (msg) == GST_OBJECT (data.pipeline)) {
  gst_message_parse_state_changed (msg, &old_state, &new_state,
      &pending_state);
}
```

管线内部每个 element 都可能发出状态变化消息。demo 只关心 pipeline 本身的状态变化，所以用 `GST_MESSAGE_SRC (msg) == GST_OBJECT (data.pipeline)` 过滤。

运行时通常能看到类似输出：

```text
Pipeline state changed from NULL to READY:
Pipeline state changed from READY to PAUSED:
Received new pad 'src_0' from 'source':
It has type 'video/x-raw' which is not raw audio. Ignoring.
Received new pad 'src_1' from 'source':
Link succeeded (type 'audio/x-raw').
Pipeline state changed from PAUSED to PLAYING:
End-Of-Stream reached.
```

实际 pad 名称和顺序可能会随媒体内容、插件版本变化。

## pad_added_handler 详解

回调函数签名：

```c
static void
pad_added_handler (GstElement * src, GstPad * new_pad, CustomData * data)
```

参数含义：

| 参数 | 含义 |
| --- | --- |
| `src` | 发出信号的 element，这里是 `uridecodebin` |
| `new_pad` | 刚刚动态创建出来的 source pad |
| `data` | 注册信号时传入的 `CustomData` |

### 1. 获取 audioconvert 的 sink pad

```c
GstPad *sink_pad = gst_element_get_static_pad (data->convert, "sink");
```

`audioconvert` 的 sink pad 是静态 pad，创建 element 时就已经存在，所以可以用 `gst_element_get_static_pad()` 直接获取。

后面要做的连接就是：

```text
new_pad -> audioconvert:sink
```

### 2. 避免重复连接

```c
if (gst_pad_is_linked (sink_pad)) {
  g_print ("We are already linked. Ignoring.\n");
  goto exit;
}
```

`uridecodebin` 可能创建多个 pad。这个 demo 只播放一条音频流，所以如果 `audioconvert` 的 sink pad 已经被连接，就忽略后续 pad。

### 3. 检查新 pad 的类型

```c
new_pad_caps = gst_pad_get_current_caps (new_pad);
new_pad_struct = gst_caps_get_structure (new_pad_caps, 0);
new_pad_type = gst_structure_get_name (new_pad_struct);
```

`GstCaps` 描述 pad 上能传输的数据类型和格式。这里读取新 pad 当前 caps 的第一个 structure，并取出 media type。

例如：

```text
audio/x-raw
video/x-raw
```

这个 demo 只想接音频，所以检查：

```c
if (!g_str_has_prefix (new_pad_type, "audio/x-raw")) {
  g_print ("It has type '%s' which is not raw audio. Ignoring.\n",
      new_pad_type);
  goto exit;
}
```

如果新 pad 是视频，就忽略。只有 `audio/x-raw` 才会进入下一步。

### 4. 连接 pad

```c
ret = gst_pad_link (new_pad, sink_pad);
```

`gst_element_link_many()` 适合连接静态 pad 明确的 element；这里要连接的是运行时拿到的具体 pad，所以使用 `gst_pad_link()`。

连接成功后，完整音频路径就变成：

```text
uridecodebin:audio_src -> audioconvert -> audioresample -> autoaudiosink
```

### 5. 释放引用

```c
if (new_pad_caps != NULL)
  gst_caps_unref (new_pad_caps);

gst_object_unref (sink_pad);
```

`gst_pad_get_current_caps()` 和 `gst_element_get_static_pad()` 都会返回需要调用者释放的引用。回调结束前必须释放，避免引用泄漏。

## 资源清理

主循环结束后：

```c
gst_object_unref (bus);
gst_element_set_state (data.pipeline, GST_STATE_NULL);
gst_object_unref (data.pipeline);
```

清理顺序是：

1. 释放 bus。
2. 把 pipeline 设置回 `NULL` 状态，停止所有内部资源。
3. 释放 pipeline。pipeline 会连带释放其中的 element。

## 为什么这个例子叫 Dynamic Pipelines

在 Basic Tutorial 2 里，所有 element 和 pad 都可以在启动前静态连接；而这个例子里，`uridecodebin` 的输出取决于媒体内容：

- 如果 URI 是纯音频，它可能只生成音频 pad。
- 如果 URI 是视频文件，它可能生成视频 pad 和音频 pad。
- 如果媒体包含字幕或多路音轨，还可能生成更多 pad。

因此应用程序要在运行时响应 `pad-added`，根据 caps 决定是否连接。这就是动态管线的核心思想。

## 关键 API 总结

| API | 作用 |
| --- | --- |
| `gst_element_factory_make()` | 创建 element |
| `gst_pipeline_new()` | 创建 pipeline |
| `gst_bin_add_many()` | 把 element 加入 bin/pipeline |
| `gst_element_link_many()` | 连接静态链路 |
| `g_object_set()` | 设置 GObject 属性 |
| `g_signal_connect()` | 监听 GObject 信号 |
| `gst_element_set_state()` | 切换 element/pipeline 状态 |
| `gst_element_get_bus()` | 获取 pipeline 的 bus |
| `gst_bus_timed_pop_filtered()` | 阻塞等待指定类型消息 |
| `gst_message_parse_error()` | 解析错误消息 |
| `gst_message_parse_state_changed()` | 解析状态变化消息 |
| `gst_element_get_static_pad()` | 获取静态 pad |
| `gst_pad_get_current_caps()` | 获取 pad 当前 caps |
| `gst_pad_link()` | 连接两个具体 pad |

## 可尝试的改动

- 把 URI 换成一个纯音频文件，观察是否只出现音频 pad。
- 在 `pad_added_handler()` 中打印完整 caps，观察 `audio/x-raw` 后面包含的采样率、声道数、格式等字段。
- 增加视频分支，把 `video/x-raw` 接到 `videoconvert -> autovideosink`，实现同时播放音频和视频。

