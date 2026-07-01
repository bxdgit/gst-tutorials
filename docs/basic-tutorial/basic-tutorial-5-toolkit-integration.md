# Basic Tutorial 5: Toolkit Integration 代码讲解

本文讲解 [src/basic-tutorial/basic-tutorial-5.c](../../src/basic-tutorial/basic-tutorial-5.c)，对应 GStreamer 官方教程：
<https://gstreamer.freedesktop.org/documentation/tutorials/basic/toolkit-integration.html?gi-language=c>

这个 demo 的主题是 **GUI 工具包集成**：用 GTK 做一个简单播放器界面，让 GStreamer 负责媒体播放，让 GTK 负责窗口、按钮、进度条和文本显示。

官方教程强调的几个核心点是：

- 如何让 GStreamer 把视频画面渲染到指定的 GTK widget 中，而不是自己创建窗口。
- 如何从 GStreamer 查询播放状态并持续刷新 GUI。
- 如何把 GStreamer 工作线程里的事件安全地转发到 GUI 主线程。
- 如何只订阅自己关心的 bus 消息，而不是手动解析所有消息。

## 这个 Demo 做了什么

程序播放远程 WebM 文件：

```text
https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm
```

运行后会打开一个 GTK 窗口，界面大致包含：

- 视频显示区域。
- 播放、暂停、停止按钮。
- 一个表示播放位置的 slider。
- 右侧文本区域，用来显示视频、音频、字幕流的 metadata。

整体结构可以理解为：

```text
GTK 主循环
  ├── 按钮回调：控制 playbin 状态
  ├── slider 回调：对 playbin 执行 seek
  ├── 定时器：查询 playbin 位置并刷新 slider
  └── bus 消息回调：处理 error/eos/state/application

GStreamer playbin
  ├── 播放 URI
  ├── 输出视频到 GTK sink widget
  ├── 输出音频到默认音频设备
  └── 发现 metadata 后发出 tags-changed 信号
```

## CustomData 数据结构

```c
typedef struct _CustomData {
  GstElement *playbin;

  GtkWidget *sink_widget;
  GtkWidget *slider;
  GtkWidget *streams_list;
  gulong slider_update_signal_id;

  GstState state;
  gint64 duration;
} CustomData;
```

字段含义如下：

| 字段 | 作用 |
| --- | --- |
| `playbin` | 播放器 element，内部自动构建播放管线 |
| `sink_widget` | GStreamer 视频 sink 提供的 GTK widget，视频会渲染到这里 |
| `slider` | 播放进度条，也可以拖动触发 seek |
| `streams_list` | 显示媒体流 metadata 的文本控件 |
| `slider_update_signal_id` | slider 的 `value-changed` 信号 ID，用于临时屏蔽回调 |
| `state` | 当前 GStreamer 播放状态 |
| `duration` | 媒体总时长，单位纳秒 |

这里的设计重点是：GTK 控件和 GStreamer element 都放进同一个结构体，方便各类回调函数访问共享状态。

## 控制按钮回调

播放按钮：

```c
static void play_cb (GtkButton *button, CustomData *data) {
  gst_element_set_state (data->playbin, GST_STATE_PLAYING);
}
```

暂停按钮：

```c
static void pause_cb (GtkButton *button, CustomData *data) {
  gst_element_set_state (data->playbin, GST_STATE_PAUSED);
}
```

停止按钮：

```c
static void stop_cb (GtkButton *button, CustomData *data) {
  gst_element_set_state (data->playbin, GST_STATE_READY);
}
```

这三个按钮本质上都是把用户操作翻译成 `playbin` 的状态切换：

| UI 操作 | GStreamer 状态 |
| --- | --- |
| Play | `GST_STATE_PLAYING` |
| Pause | `GST_STATE_PAUSED` |
| Stop | `GST_STATE_READY` |

这里 Stop 没有切到 `NULL`，而是切到 `READY`。这样可以停止播放并释放一部分运行时资源，同时还保留 element 可继续使用，用户再次点击 Play 可以继续让它进入播放流程。

## 关闭窗口

```c
static void delete_event_cb (GtkWidget *widget, GdkEvent *event,
    CustomData *data) {
  stop_cb (NULL, data);
  gtk_main_quit ();
}
```

窗口关闭时，程序先停止播放，再退出 GTK 主循环。`gtk_main()` 返回以后，`main()` 函数会继续执行后面的资源释放逻辑。

## Slider 拖动与 Seek

```c
static void slider_cb (GtkRange *range, CustomData *data) {
  gdouble value = gtk_range_get_value (GTK_RANGE (data->slider));
  gst_element_seek_simple (data->playbin, GST_FORMAT_TIME,
      GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT,
      (gint64)(value * GST_SECOND));
}
```

slider 的数值单位是秒，而 GStreamer 的时间单位是纳秒，所以 seek 时要乘以：

```c
GST_SECOND
```

seek 使用了两个 flag：

| Flag | 作用 |
| --- | --- |
| `GST_SEEK_FLAG_FLUSH` | 清空旧数据，让 seek 更快生效 |
| `GST_SEEK_FLAG_KEY_UNIT` | 尽量 seek 到关键帧附近，更适合视频播放 |

也就是说，拖动进度条就是对 `playbin` 发起一次时间格式的 seek。

## 创建 GTK 界面

`create_ui()` 负责创建所有 GTK 控件，并注册控件回调。

窗口：

```c
main_window = gtk_window_new (GTK_WINDOW_TOPLEVEL);
g_signal_connect (G_OBJECT (main_window), "delete-event",
    G_CALLBACK (delete_event_cb), data);
```

按钮：

```c
play_button = gtk_button_new_from_icon_name ("media-playback-start",
    GTK_ICON_SIZE_SMALL_TOOLBAR);
pause_button = gtk_button_new_from_icon_name ("media-playback-pause",
    GTK_ICON_SIZE_SMALL_TOOLBAR);
stop_button = gtk_button_new_from_icon_name ("media-playback-stop",
    GTK_ICON_SIZE_SMALL_TOOLBAR);
```

进度条：

```c
data->slider = gtk_scale_new_with_range (GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
gtk_scale_set_draw_value (GTK_SCALE (data->slider), 0);
data->slider_update_signal_id = g_signal_connect (G_OBJECT (data->slider),
    "value-changed", G_CALLBACK (slider_cb), data);
```

右侧 metadata 文本区域：

```c
data->streams_list = gtk_text_view_new ();
gtk_text_view_set_editable (GTK_TEXT_VIEW (data->streams_list), FALSE);
```

布局上使用了几个 `GtkBox`：

```text
main_window
└── main_box (vertical)
    ├── main_hbox (horizontal)
    │   ├── sink_widget      视频区域
    │   └── streams_list     流信息
    └── controls (horizontal)
        ├── play_button
        ├── pause_button
        ├── stop_button
        └── slider
```

其中最关键的是：

```c
gtk_box_pack_start (GTK_BOX (main_hbox), data->sink_widget, TRUE, TRUE, 0);
```

`data->sink_widget` 不是普通手写的 GTK 控件，而是由 GStreamer 的 GTK video sink 创建出来的 widget。把它放进 GTK 布局后，视频就会显示在应用窗口里。

## 创建视频 Sink

`main()` 中先创建 `playbin`：

```c
data.playbin = gst_element_factory_make ("playbin", "playbin");
```

然后尝试创建 OpenGL 版本的视频 sink：

```c
videosink = gst_element_factory_make ("glsinkbin", "glsinkbin");
gtkglsink = gst_element_factory_make ("gtkglsink", "gtkglsink");
```

如果都创建成功：

```c
g_object_set (videosink, "sink", gtkglsink, NULL);
g_object_get (gtkglsink, "widget", &data.sink_widget, NULL);
```

这里有两层：

- `gtkglsink` 真正负责把视频渲染到 GTK widget。
- `glsinkbin` 包一层 OpenGL sink，方便和 `playbin` 对接。

如果 OpenGL sink 创建失败，就回退到普通 GTK sink：

```c
videosink = gst_element_factory_make ("gtksink", "gtksink");
g_object_get (videosink, "widget", &data.sink_widget, NULL);
```

不管哪种方式，最终目的都是拿到一个 GTK widget：

```c
data.sink_widget
```

然后把这个 sink 设置给 `playbin`：

```c
g_object_set (data.playbin, "video-sink", videosink, NULL);
```

这就是“让 GStreamer 输出视频到指定 GTK 控件”的核心。

## 设置 URI

```c
g_object_set (data.playbin, "uri",
    "https://gstreamer.freedesktop.org/data/media/sintel_trailer-480p.webm",
    NULL);
```

`playbin` 内部会根据 URI 自动完成下载、demux、decode、音视频输出等工作。这个 demo 不需要手动搭建 `uridecodebin -> decode -> convert -> sink` 这样的管线。

## 定时刷新 GUI

程序注册一个 GLib 定时器：

```c
g_timeout_add_seconds (1, (GSourceFunc)refresh_ui, &data);
```

这表示 GLib 主循环每秒调用一次 `refresh_ui()`。注意，GTK 主循环本身就是基于 GLib main loop 的，所以这个定时器会在 GUI 主线程执行，适合更新 GTK 控件。

`refresh_ui()` 首先检查当前状态：

```c
if (data->state < GST_STATE_PAUSED)
  return TRUE;
```

只有在 `PAUSED` 或 `PLAYING` 状态下，才尝试查询 duration 和 position。因为此时媒体信息通常已经可用。

### 查询总时长并设置 Slider 范围

```c
if (!GST_CLOCK_TIME_IS_VALID (data->duration)) {
  if (gst_element_query_duration (data->playbin, GST_FORMAT_TIME,
      &data->duration)) {
    gtk_range_set_range (GTK_RANGE (data->slider), 0,
        (gdouble)data->duration / GST_SECOND);
  }
}
```

`duration` 是纳秒，slider 使用秒，所以这里除以 `GST_SECOND`。

设置范围后，slider 的最大值就是视频总秒数。

### 查询当前位置并更新 Slider

```c
if (gst_element_query_position (data->playbin, GST_FORMAT_TIME, &current)) {
  g_signal_handler_block (data->slider, data->slider_update_signal_id);
  gtk_range_set_value (GTK_RANGE (data->slider),
      (gdouble)current / GST_SECOND);
  g_signal_handler_unblock (data->slider, data->slider_update_signal_id);
}
```

这里最容易忽略的是 signal block。

程序更新 slider 的值时，GTK 会触发 `value-changed` 信号。如果不屏蔽这个信号，就会调用 `slider_cb()`，导致程序以为是用户拖动 slider，又执行一次 seek。

所以正确流程是：

```text
临时屏蔽 value-changed
  -> 程序主动更新 slider 显示值
恢复 value-changed
```

这样 GUI 能显示最新进度，但不会产生用户没有请求的 seek。

`refresh_ui()` 返回 `TRUE`，表示定时器继续保留，下次还会再调用。

## Bus 消息：从轮询改成信号

前面的教程常用：

```c
gst_bus_timed_pop_filtered()
```

这个 demo 换成了 bus signal watch：

```c
bus = gst_element_get_bus (data.playbin);
gst_bus_add_signal_watch (bus);
g_signal_connect (G_OBJECT (bus), "message::error",
    (GCallback)error_cb, &data);
g_signal_connect (G_OBJECT (bus), "message::eos",
    (GCallback)eos_cb, &data);
g_signal_connect (G_OBJECT (bus), "message::state-changed",
    (GCallback)state_changed_cb, &data);
g_signal_connect (G_OBJECT (bus), "message::application",
    (GCallback)application_cb, &data);
gst_object_unref (bus);
```

`gst_bus_add_signal_watch()` 会把 bus 消息集成进 GLib main loop。之后应用可以用 GObject 信号的方式订阅特定消息类型：

| 信号 | 回调 |
| --- | --- |
| `message::error` | `error_cb()` |
| `message::eos` | `eos_cb()` |
| `message::state-changed` | `state_changed_cb()` |
| `message::application` | `application_cb()` |

这样就不用在一个大 `switch` 里手动过滤所有消息了。GUI 程序通常更适合这种事件驱动写法。

## ERROR 和 EOS 处理

错误消息：

```c
gst_message_parse_error (msg, &err, &debug_info);
gst_element_set_state (data->playbin, GST_STATE_READY);
```

发生错误时，打印错误信息，然后把 `playbin` 切回 `READY`，停止播放。

EOS 消息：

```c
g_print ("End-Of-Stream reached.\n");
gst_element_set_state (data->playbin, GST_STATE_READY);
```

播放到结尾时也切回 `READY`。

## State Changed 处理

```c
gst_message_parse_state_changed (msg, &old_state, &new_state, &pending_state);
if (GST_MESSAGE_SRC (msg) == GST_OBJECT (data->playbin)) {
  data->state = new_state;
  g_print ("State set to %s\n", gst_element_state_get_name (new_state));
  if (old_state == GST_STATE_READY && new_state == GST_STATE_PAUSED) {
    refresh_ui (data);
  }
}
```

状态变化消息可能来自内部很多 element，所以必须过滤来源，只处理 `playbin` 自己发出的状态变化。

当状态从 `READY` 到 `PAUSED` 时，媒体信息通常已经可查询。demo 立刻调用一次 `refresh_ui()`，这样 slider 的 duration 和 position 能更快显示出来，不必等下一次 1 秒定时器。

## Metadata 信号与线程问题

`playbin` 会在发现流 metadata 时发出这些信号：

```c
g_signal_connect (G_OBJECT (data.playbin), "video-tags-changed",
    (GCallback) tags_cb, &data);
g_signal_connect (G_OBJECT (data.playbin), "audio-tags-changed",
    (GCallback) tags_cb, &data);
g_signal_connect (G_OBJECT (data.playbin), "text-tags-changed",
    (GCallback) tags_cb, &data);
```

注意：这些回调可能运行在 GStreamer 的工作线程中。很多 GUI 工具包，包括 GTK，都要求只能在主线程修改 UI。如果在 `tags_cb()` 里直接更新 `GtkTextView`，可能出问题。

所以 demo 没有在 `tags_cb()` 中直接调用 GTK API，而是往 bus 上投递一条 application message：

```c
gst_element_post_message (playbin,
  gst_message_new_application (GST_OBJECT (playbin),
    gst_structure_new_empty ("tags-changed")));
```

随后这条消息会被 GLib/GTK 主循环收到，并触发：

```c
application_cb()
```

这就是线程切换的关键路径：

```text
GStreamer 工作线程
  -> tags_cb()
  -> gst_element_post_message(... "tags-changed")
  -> bus message::application
  -> GTK 主线程 application_cb()
  -> analyze_streams()
  -> 更新 GtkTextView
```

这套方式非常实用：工作线程只负责发消息，真正的 UI 更新统一放到主线程。

## 解析并显示流信息

`application_cb()` 只处理名为 `tags-changed` 的 application message：

```c
if (g_strcmp0 (gst_structure_get_name (gst_message_get_structure (msg)),
    "tags-changed") == 0) {
  analyze_streams (data);
}
```

`analyze_streams()` 先清空右侧文本框：

```c
text = gtk_text_view_get_buffer (GTK_TEXT_VIEW (data->streams_list));
gtk_text_buffer_set_text (text, "", -1);
```

然后读取 `playbin` 里有多少路视频、音频、字幕：

```c
g_object_get (data->playbin, "n-video", &n_video, NULL);
g_object_get (data->playbin, "n-audio", &n_audio, NULL);
g_object_get (data->playbin, "n-text", &n_text, NULL);
```

对每一路流，再通过 `playbin` 的 action signal 取 tags：

```c
g_signal_emit_by_name (data->playbin, "get-video-tags", i, &tags);
g_signal_emit_by_name (data->playbin, "get-audio-tags", i, &tags);
g_signal_emit_by_name (data->playbin, "get-text-tags", i, &tags);
```

然后从 `GstTagList` 里取出信息：

| Tag | 含义 |
| --- | --- |
| `GST_TAG_VIDEO_CODEC` | 视频编码格式 |
| `GST_TAG_AUDIO_CODEC` | 音频编码格式 |
| `GST_TAG_LANGUAGE_CODE` | 语言 |
| `GST_TAG_BITRATE` | 比特率 |

最后用 `gtk_text_buffer_insert_at_cursor()` 把信息写到右侧文本控件中。

## main 函数流程

`main()` 的整体顺序如下：

1. `gtk_init()` 初始化 GTK。
2. `gst_init()` 初始化 GStreamer。
3. 初始化 `CustomData`，把 `duration` 设为 `GST_CLOCK_TIME_NONE`。
4. 创建 `playbin`、`glsinkbin`、`gtkglsink`，失败时回退到 `gtksink`。
5. 从 video sink 获取 GTK widget。
6. 设置播放 URI。
7. 设置 `playbin` 的 `video-sink`。
8. 连接 tags changed 信号。
9. 创建 GTK 界面。
10. 给 bus 添加 signal watch，并注册关心的消息回调。
11. 把 `playbin` 设置为 `PLAYING`。
12. 注册每秒调用一次的 `refresh_ui()`。
13. 进入 `gtk_main()`。
14. 退出后把 `playbin` 设置为 `NULL` 并释放资源。

## 编译提示

官方教程给出的 Linux 编译方式类似：

```sh
gcc basic-tutorial-5.c -o basic-tutorial-5 \
  `pkg-config --cflags --libs gtk+-3.0 gstreamer-1.0`
```

在本仓库中源码位于 `src/basic-tutorial/basic-tutorial-5.c`，如果要手动编译，可以按项目目录调整输入输出路径。

运行时还需要系统安装相应的 GStreamer 插件，例如 `gtkglsink`、`gtksink`、`glsinkbin` 等所在插件包。缺少 OpenGL GTK sink 时，代码会尝试回退到 `gtksink`。

## 关键 API 总结

| API / 概念 | 作用 |
| --- | --- |
| `playbin` | 高级播放器 element，内部自动构建播放管线 |
| `video-sink` 属性 | 指定 `playbin` 使用哪个视频输出 sink |
| `gtkglsink` / `gtksink` | 能提供 GTK widget 的视频 sink |
| `g_object_get (..., "widget", ...)` | 从 GTK video sink 取出视频显示控件 |
| `gtk_button_new_from_icon_name()` | 创建带图标的 GTK 按钮 |
| `gtk_scale_new_with_range()` | 创建 slider |
| `gst_element_seek_simple()` | 根据 slider 位置执行 seek |
| `g_timeout_add_seconds()` | 注册 GLib 定时器，周期刷新 UI |
| `gst_element_query_duration()` | 查询媒体总时长 |
| `gst_element_query_position()` | 查询当前播放位置 |
| `g_signal_handler_block()` | 临时屏蔽 signal，避免程序更新 slider 时触发 seek |
| `gst_bus_add_signal_watch()` | 把 bus 消息接入 GLib main loop |
| `message::error` / `message::eos` | 只订阅指定类型 bus 消息 |
| `gst_element_post_message()` | 从 GStreamer 回调里向 bus 投递消息 |
| `gst_message_new_application()` | 创建应用自定义消息 |
| `GstTagList` | 保存媒体 metadata |

## 这篇教程的核心思想

这个 demo 已经接近一个真正播放器的骨架：

- GStreamer 负责播放和媒体解析。
- GTK 负责窗口和用户交互。
- 用户操作通过 GTK 回调转成 GStreamer 状态切换或 seek。
- 播放状态通过 GStreamer query 和 bus message 回到 GTK。
- 可能来自 GStreamer 工作线程的事件，通过 application bus message 安全转交给 GUI 主线程。

理解这套结构后，就可以继续扩展出更完整的播放器功能，例如音量控制、播放列表、全屏、字幕选择、音轨切换、缓冲显示等。

## 可尝试的改动

- 给界面增加一个音量 slider，并设置 `playbin` 的 `volume` 属性。
- 在右侧文本区显示更多 tag，例如标题、艺术家、容器格式。
- 把 `g_timeout_add_seconds()` 改成 `g_timeout_add()`，用更高频率刷新进度条。
- 给 EOS 处理增加“回到开头”的 seek，让播放结束后 slider 回到 0。
- 增加音轨或字幕选择控件，配合 `playbin` 的 stream 相关属性实现切换。

