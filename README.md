# GStreamer Tutorials Notes

这个仓库用于学习和整理 GStreamer Basic Tutorial 系列，包括示例源码、中文讲解文档和统一编译入口。

## Environment

目标验证环境使用的 GStreamer 版本：

```sh
$ gst-inspect-1.0 --version
gst-inspect-1.0 version 1.20.3
GStreamer 1.20.3
https://launchpad.net/distros/ubuntu/+source/gstreamer1.0
```

当前开发机可能没有安装 GStreamer 开发环境，因此编译验证以目标机器为准。

## Directory Layout

```text
.
├── Makefile
├── buils.sh
├── bin/
├── docs/
│   └── basic-tutorial/
└── src/
    └── basic-tutorial/
```

- `src/basic-tutorial/`: Basic Tutorial 示例 C 源码。
- `docs/basic-tutorial/`: 对应教程的中文讲解文档和系列知识图谱。
- `bin/`: 编译输出目录。
- `Makefile`: 统一编译入口。
- `buils.sh`: 兼容旧入口，内部直接调用 `make "$@"`。

## Build

编译全部可用源码：

```sh
make
```

编译单个教程：

```sh
make basic-tutorial-3
make basic-tutorial-8
make basic-tutorial-13
```

清理编译产物：

```sh
make clean
```

也可以使用旧脚本入口：

```sh
./buils.sh
./buils.sh basic-tutorial-5
```

## Dependencies

Makefile 通过 `pkg-config` 检查依赖。目标机器需要安装对应开发包，至少包括：

```text
gstreamer-1.0
gstreamer-audio-1.0
gstreamer-pbutils-1.0
gtk+-3.0
```

不同示例依赖不同：

| Tutorial | pkg-config packages |
| --- | --- |
| `basic-tutorial-1/2/3/4/6/7/12/13` | `gstreamer-1.0` |
| `basic-tutorial-5` | `gtk+-3.0 gstreamer-1.0` |
| `basic-tutorial-8` | `gstreamer-1.0 gstreamer-audio-1.0` |
| `basic-tutorial-9` | `gstreamer-1.0 gstreamer-pbutils-1.0` |

如果依赖缺失，`make` 会提示缺少的 `pkg-config` 包。

## Run

编译后可直接运行：

```sh
./bin/basic-tutorial-3
./bin/basic-tutorial-8
./bin/basic-tutorial-13
```

部分示例会打开音频或视频输出窗口，目标机器需要具备相应的音视频输出环境和 GStreamer 插件。

常用调试方式：

```sh
GST_DEBUG=2 ./bin/basic-tutorial-12
GST_DEBUG=2,GST_CAPS:6 ./bin/basic-tutorial-6
GST_DEBUG=2,GST_EVENT:5,GST_SEEK:5 ./bin/basic-tutorial-13
```

## Documentation

建议先看总览：

- [GStreamer Basic Tutorial 系列知识图谱总结](docs/basic-tutorial/basic-tutorial-series-knowledge-map.md)

分篇文档：

- [Basic Tutorial 1: Hello World](docs/basic-tutorial/basic-tutorial-1-hello-world.md)
- [Basic Tutorial 2: GStreamer Concepts](docs/basic-tutorial/basic-tutorial-2-concepts.md)
- [Basic Tutorial 3: Dynamic Pipelines](docs/basic-tutorial/basic-tutorial-3-dynamic-pipelines.md)
- [Basic Tutorial 4: Time Management](docs/basic-tutorial/basic-tutorial-4-time-management.md)
- [Basic Tutorial 5: Toolkit Integration](docs/basic-tutorial/basic-tutorial-5-toolkit-integration.md)
- [Basic Tutorial 6: Media Formats and Pad Capabilities](docs/basic-tutorial/basic-tutorial-6-media-formats-and-pad-capabilities.md)
- [Basic Tutorial 7: Multithreading and Pad Availability](docs/basic-tutorial/basic-tutorial-7-multithreading-and-pad-availability.md)
- [Basic Tutorial 8: Short-cutting the Pipeline](docs/basic-tutorial/basic-tutorial-8-short-cutting-the-pipeline.md)
- [Basic Tutorial 9: Media Information Gathering](docs/basic-tutorial/basic-tutorial-9-media-information-gathering.md)
- [Basic Tutorial 10: GStreamer Tools](docs/basic-tutorial/basic-tutorial-10-gstreamer-tools.md)
- [Basic Tutorial 11: Debugging Tools](docs/basic-tutorial/basic-tutorial-11-debugging-tools.md)
- [Basic Tutorial 12: Streaming](docs/basic-tutorial/basic-tutorial-12-streaming.md)
- [Basic Tutorial 13: Playback Speed](docs/basic-tutorial/basic-tutorial-13-playback-speed.md)
- [Basic Tutorial 14: Handy Elements](docs/basic-tutorial/basic-tutorial-14-handy-elements.md)
- [Basic Tutorial 16: Platform-specific Elements](docs/basic-tutorial/basic-tutorial-16-platform-specific-elements.md)

## Notes

- 本仓库源码和文档主要围绕 GStreamer Basic Tutorial 系列。
- 有些教程是工具或概念讲解，没有对应 C 源码。
- 示例中的网络 URI 依赖外部网络和对应插件，离线环境下建议改成本地 `file://` URI。
- `basic-tutorial-13` 的变速和倒放能力依赖媒体格式、demuxer、decoder 和 source，对本地文件通常更可靠。
