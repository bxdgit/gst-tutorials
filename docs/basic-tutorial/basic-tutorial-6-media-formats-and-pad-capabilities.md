# Basic Tutorial 6: Media Formats and Pad Capabilities 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-6.c](../../src/basic-tutorial/basic-tutorial-6.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/media-formats-and-pad-capabilities.html?gi-language=c>

这个 demo 的主题是 **媒体格式与 Pad Capabilities**，也就是 GStreamer 里常说的 **Caps**。Caps 用来描述一个 pad 可以传输什么样的数据，例如原始音频、H.264 视频、采样率、声道数、像素格式、分辨率等。

前几个教程里，caps 多数由 GStreamer 自动处理。这篇教程把它拿出来单独观察：程序先打印 element factory 上的 pad template caps，再启动一个简单管线，并在每次状态变化时打印 sink pad 当前 caps，观察 caps 如何从“可能支持很多格式”逐渐变成“已经协商好的具体格式”。

## 这个 Demo 做了什么

程序构建了一个非常简单的音频管线：

```text
audiotestsrc -> autoaudiosink
```

其中：

- `audiotestsrc` 生成测试音频信号。
- `autoaudiosink` 自动选择系统可用的音频输出设备。

程序会做几件事：

1. 用 `gst_element_factory_find()` 找到 `audiotestsrc` 和 `autoaudiosink` 的 element factory。
2. 打印这两个 factory 的 pad template 信息。
3. 用 factory 创建实际 element。
4. 连接 `audiotestsrc -> autoaudiosink`。
5. 在 `NULL` 状态下打印 sink pad caps。
6. 启动 pipeline。
7. 每当 pipeline 状态变化时，再打印 sink pad caps。

核心观察点是：随着 pipeline 状态变化，sink pad 的 caps 会从宽泛范围逐步收敛成协商后的具体格式。

## 什么是 Pad

Pad 是 element 之间传输数据的端口：

```text
source element 的 src pad -> sink element 的 sink pad
```

例如：

```text
audiotestsrc:src -> autoaudiosink:sink
```

一个 element 可以有多个 pad，也可能有动态 pad。前面的 Basic Tutorial 3 就讲过 `uridecodebin` 会在运行时动态创建 pad。

## 什么是 Caps

Caps 是 capabilities 的简称，用来描述 pad 能传输的数据类型和格式。

例如音频 caps 可能长这样：

```text
audio/x-raw
          format: S16LE
            rate: 44100
        channels: 2
```

含义是：

- 数据类型是原始音频：`audio/x-raw`
- 采样格式是 16-bit little-endian：`S16LE`
- 采样率是 44100 Hz
- 声道数是 2

Caps 也可能包含范围或列表，例如：

```text
rate: [ 1, 2147483647 ]
format: { S16LE, S32LE, F32LE }
```

这表示 pad 支持很多可能的格式，但运行时真正流过 pad 的数据必须是一个确定格式。两个 pad link 以后，会通过 negotiation 协商出双方都支持的具体 caps。

## 什么是 Pad Template

Pad template 是 element factory 层面的 pad 模板。它描述“这个类型的 element 可能拥有哪些 pad，以及这些 pad 理论上支持哪些 caps”。

Pad template 常见信息包括：

| 信息 | 含义 |
| --- | --- |
| direction | pad 方向，`SRC` 或 `SINK` |
| name_template | pad 名称模板，例如 `src`、`sink`、`audio_%u` |
| presence | pad 何时存在，例如 always、sometimes、request |
| static caps | 这个 pad 理论上支持的能力集合 |

Pad template 是协商的起点。GStreamer 可以先看两个 element 的 pad template caps 是否有交集。如果完全没有交集，就没必要继续协商，两个 element 也无法 link。

## 打印 Caps 的辅助函数

### print_field

```c
static gboolean print_field (GQuark field, const GValue * value,
    gpointer pfx) {
  gchar *str = gst_value_serialize (value);

  g_print ("%s  %15s: %s\n", (gchar *) pfx,
      g_quark_to_string (field), str);
  g_free (str);
  return TRUE;
}
```

`GstStructure` 里的字段名是 `GQuark`，字段值是 `GValue`。这个函数把字段和值转换成适合打印的字符串：

- `g_quark_to_string(field)` 把字段名转成字符串。
- `gst_value_serialize(value)` 把 `GValue` 转成可读文本。

它会被 `gst_structure_foreach()` 调用，用来逐个打印 caps structure 里的字段。

### print_caps

```c
static void print_caps (const GstCaps * caps, const gchar * pfx)
```

这个函数负责把 `GstCaps` 打印成人能读懂的格式。

它先处理两个特殊情况：

```c
if (gst_caps_is_any (caps)) {
  g_print ("%sANY\n", pfx);
  return;
}
if (gst_caps_is_empty (caps)) {
  g_print ("%sEMPTY\n", pfx);
  return;
}
```

| Caps | 含义 |
| --- | --- |
| `ANY` | 任何格式都可以 |
| `EMPTY` | 没有任何可接受格式 |

然后遍历 caps 中的每个 `GstStructure`：

```c
for (i = 0; i < gst_caps_get_size (caps); i++) {
  GstStructure *structure = gst_caps_get_structure (caps, i);

  g_print ("%s%s\n", pfx, gst_structure_get_name (structure));
  gst_structure_foreach (structure, print_field, (gpointer) pfx);
}
```

一个 `GstCaps` 可以包含多个 structure。每个 structure 通常代表一种媒体类型及其字段约束，例如 `audio/x-raw` 加上 format、rate、channels 等字段。

## 打印 Pad Template 信息

```c
static void print_pad_templates_information (GstElementFactory * factory)
```

这个函数从 element factory 读取 pad template 信息：

```c
pads = gst_element_factory_get_static_pad_templates (factory);
```

然后逐个打印：

### Pad 方向

```c
if (padtemplate->direction == GST_PAD_SRC)
  g_print ("  SRC template: '%s'\n", padtemplate->name_template);
else if (padtemplate->direction == GST_PAD_SINK)
  g_print ("  SINK template: '%s'\n", padtemplate->name_template);
```

`SRC` 表示输出数据，`SINK` 表示接收数据。

### Pad 可用性

```c
if (padtemplate->presence == GST_PAD_ALWAYS)
  g_print ("    Availability: Always\n");
else if (padtemplate->presence == GST_PAD_SOMETIMES)
  g_print ("    Availability: Sometimes\n");
else if (padtemplate->presence == GST_PAD_REQUEST)
  g_print ("    Availability: On request\n");
```

三种常见可用性：

| Presence | 含义 |
| --- | --- |
| `GST_PAD_ALWAYS` | element 创建后 pad 一直存在 |
| `GST_PAD_SOMETIMES` | 运行时根据媒体内容动态出现 |
| `GST_PAD_REQUEST` | 应用需要时主动请求创建 |

`audiotestsrc` 和多数音频 sink 的基础 pad 通常都是 `Always`。而 `uridecodebin` 这类 element 常见的是 `Sometimes` 动态 pad。

### Pad Template Caps

```c
caps = gst_static_caps_get (&padtemplate->static_caps);
print_caps (caps, "      ");
gst_caps_unref (caps);
```

`padtemplate->static_caps` 是静态 caps 描述，`gst_static_caps_get()` 会把它转换成普通 `GstCaps`，方便后续统一打印。用完后需要 `gst_caps_unref()`。

## 打印运行时 Pad Capabilities

```c
static void print_pad_capabilities (GstElement *element, gchar *pad_name)
```

这个函数打印某个实际 element 的某个 pad 当前 caps。

### 获取静态 Pad

```c
pad = gst_element_get_static_pad (element, pad_name);
```

这里传入的是：

```c
print_pad_capabilities (sink, "sink");
```

所以取的是 `autoaudiosink` 的 `sink` pad。

### 优先获取 Current Caps

```c
caps = gst_pad_get_current_caps (pad);
```

`current caps` 表示 pad 当前已经协商出的 caps。如果协商已经完成，它通常是固定的、具体的格式。

例如：

```text
audio/x-raw
          format: S16LE
            rate: 44100
        channels: 2
          layout: interleaved
```

### 协商未完成时查询可接受 Caps

```c
if (!caps)
  caps = gst_pad_query_caps (pad, NULL);
```

在 `NULL` 状态或协商还没完成时，`gst_pad_get_current_caps()` 可能返回 `NULL`。这时程序用 `gst_pad_query_caps()` 查询当前 pad 可接受的 caps。

这两者的区别很重要：

| API | 含义 |
| --- | --- |
| `gst_pad_get_current_caps()` | 当前已经协商好的 caps，可能为空 |
| `gst_pad_query_caps()` | 当前可接受的 caps，可能仍然包含范围和多个候选格式 |

也就是说，`get_current_caps()` 回答“现在实际是什么格式”，`query_caps()` 回答“现在可以接受哪些格式”。

### 释放引用

```c
gst_caps_unref (caps);
gst_object_unref (pad);
```

取到的 caps 和 pad 引用都需要释放。

## 为什么这次用 Element Factory

前几个教程常用：

```c
gst_element_factory_make ("audiotestsrc", "source");
```

这个 demo 拆成两步：

```c
source_factory = gst_element_factory_find ("audiotestsrc");
sink_factory = gst_element_factory_find ("autoaudiosink");
```

然后：

```c
source = gst_element_factory_create (source_factory, "source");
sink = gst_element_factory_create (sink_factory, "sink");
```

原因是 pad template 信息属于 factory 层面。也就是说，不需要真正创建 element，就可以先查看这个类型的 element 理论上拥有哪些 pad、支持哪些 caps。

可以把 `gst_element_factory_make()` 理解成：

```text
gst_element_factory_find() + gst_element_factory_create()
```

这个 demo 显式拿到 factory，是为了先打印 pad template。

## 创建并连接 Pipeline

```c
pipeline = gst_pipeline_new ("test-pipeline");
gst_bin_add_many (GST_BIN (pipeline), source, sink, NULL);
gst_element_link (source, sink);
```

管线结构非常简单：

```text
audiotestsrc -> autoaudiosink
```

如果 `gst_element_link()` 失败，通常说明两个 element 的 pad caps 没有共同子集，或者缺少必要插件、设备不可用等。Caps 正是判断 element 能不能理解彼此数据格式的关键依据。

## NULL 状态下打印 Caps

```c
g_print ("In NULL state:\n");
print_pad_capabilities (sink, "sink");
```

此时 pipeline 还没有启动，pad caps 通常还没有完成协商。

所以 `gst_pad_get_current_caps()` 很可能拿不到结果，程序会转而调用 `gst_pad_query_caps()`。打印出来的通常是比较宽泛的 caps，可能包含多个格式、多个范围。

这代表“当前 sink pad 可以接受哪些格式”，而不是“实际正在播放什么格式”。

## 启动 Pipeline 并观察状态变化

```c
ret = gst_element_set_state (pipeline, GST_STATE_PLAYING);
```

启动后，GStreamer 会让管线经过状态迁移。程序监听 bus：

```c
msg = gst_bus_timed_pop_filtered (bus, GST_CLOCK_TIME_NONE,
    GST_MESSAGE_ERROR | GST_MESSAGE_EOS | GST_MESSAGE_STATE_CHANGED);
```

收到 pipeline 本身的 `STATE_CHANGED` 消息时：

```c
gst_message_parse_state_changed (msg, &old_state, &new_state,
    &pending_state);
g_print ("\nPipeline state changed from %s to %s:\n",
    gst_element_state_get_name (old_state),
    gst_element_state_get_name (new_state));
print_pad_capabilities (sink, "sink");
```

这会在状态变化时打印 sink pad caps。

通常可以观察到：

```text
NULL 状态：caps 很宽泛，表示可接受格式
READY/PAUSED 过程中：caps 逐步结合设备能力和上下游限制收敛
PLAYING 状态：caps 通常变成固定格式
```

实际输出会因平台、音频设备、GStreamer 插件不同而变化。官方教程也提醒：有些 element 会查询底层硬件能力，因此 caps 可能随平台甚至运行环境而不同。

## Caps Negotiation 是什么

Caps negotiation 可以理解为上下游 pad 的格式协商过程。

例如：

```text
audiotestsrc 能输出：
  audio/x-raw, rate = 多种范围, channels = 多种范围, format = 多种格式

autoaudiosink 能接受：
  audio/x-raw, rate = 设备支持的范围, channels = 设备支持的范围, format = 设备支持的格式

协商后得到：
  audio/x-raw, rate = 44100, channels = 2, format = S16LE
```

协商成功后，数据流过 pad 时必须符合这个具体格式。协商失败时，就会出现 link 失败或 not-negotiated 之类的错误。

## 运行时可能看到的输出形态

不同机器输出差异很大，但大致会有这些部分：

```text
Pad Templates for Audio test source:
  SRC template: 'src'
    Availability: Always
    Capabilities:
      audio/x-raw
                 format: ...
                   rate: ...
               channels: ...

Pad Templates for Auto audio sink:
  SINK template: 'sink'
    Availability: Always
    Capabilities:
      ANY

In NULL state:
Caps for the sink pad:
      audio/x-raw
                 format: ...
                   rate: ...
               channels: ...

Pipeline state changed from NULL to READY:
Caps for the sink pad:
      ...

Pipeline state changed from READY to PAUSED:
Caps for the sink pad:
      audio/x-raw
                 format: S16LE
                   rate: 44100
               channels: 2
```

`autoaudiosink` 是一个自动选择实际音频 sink 的封装 element，所以它的 template caps 可能很宽泛，甚至是 `ANY`；进入更高状态后，它内部选中具体音频 sink，caps 才会更接近真实设备能力。

## 资源清理

主循环结束后：

```c
gst_object_unref (bus);
gst_element_set_state (pipeline, GST_STATE_NULL);
gst_object_unref (pipeline);
gst_object_unref (source_factory);
gst_object_unref (sink_factory);
```

清理顺序是：

1. 释放 bus。
2. 把 pipeline 设置回 `NULL` 状态。
3. 释放 pipeline。pipeline 会释放内部 element。
4. 释放两个 element factory 引用。

## 关键 API 总结

| API / 概念 | 作用 |
| --- | --- |
| `GstCaps` | 描述 pad 可传输的数据类型和格式 |
| `GstStructure` | caps 中的一组媒体类型和字段 |
| `gst_value_serialize()` | 把 caps 字段值转成可打印字符串 |
| `gst_caps_is_any()` | 判断 caps 是否为 `ANY` |
| `gst_caps_is_empty()` | 判断 caps 是否为 `EMPTY` |
| `gst_caps_get_size()` | 获取 caps 中 structure 数量 |
| `gst_caps_get_structure()` | 取出某个 caps structure |
| `gst_structure_get_name()` | 获取 structure 的媒体类型名 |
| `gst_structure_foreach()` | 遍历 structure 字段 |
| `GstElementFactory` | element 工厂，保存 element 类型信息 |
| `gst_element_factory_find()` | 查找 element factory |
| `gst_element_factory_create()` | 通过 factory 创建 element |
| `gst_element_factory_get_static_pad_templates()` | 获取 factory 的 pad templates |
| `gst_static_caps_get()` | 把 static caps 转为 `GstCaps` |
| `gst_element_get_static_pad()` | 获取 element 上已存在的静态 pad |
| `gst_pad_get_current_caps()` | 获取当前已协商 caps |
| `gst_pad_query_caps()` | 查询当前可接受 caps |
| `gst_element_link()` | 连接两个 element，背后依赖 caps 交集 |

## 这篇教程的核心思想

Caps 是 GStreamer 判断 element 能否相连、数据格式如何确定的基础机制。

这篇 demo 展示了三件事：

- Pad template caps 描述“这个类型的 element 理论上支持什么”。
- Pad current caps 描述“当前运行时已经协商成什么”。
- Query caps 描述“当前状态下这个 pad 可以接受什么”。

理解 caps 后，遇到 `not-negotiated`、link 失败、音视频格式不匹配、硬件 sink 不支持某种格式等问题时，就有了排查方向。

## 可尝试的改动

- 把 `autoaudiosink` 换成具体 sink，例如 `alsasink` 或 `pulsesink`，比较 pad template caps 的差异。
- 把 `audiotestsrc` 换成 `videotestsrc`，再搭配视频 sink，观察 `video/x-raw` caps。
- 在 `gst_element_link()` 前分别打印 source 的 `src` pad 和 sink 的 `sink` pad caps。
- 用 `gst-inspect-1.0 audiotestsrc` 和 `gst-inspect-1.0 autoaudiosink` 对比程序打印结果。
- 故意连接不兼容的 element，观察 link 失败或 negotiation 错误。

