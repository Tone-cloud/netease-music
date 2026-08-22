# NeteasePlayer - 词典笔网易云音乐播放器插件
# FFmpeg 解码 + QAudioOutput 播放，QML 类型 NeteasePlayer

QT       += core multimedia
CONFIG   += plugin c++11
TEMPLATE = lib
TARGET   = netease_player

# 编译产物：libnetease_player.so
DESTDIR = $$PWD/../build

SOURCES += \
    plugin.cpp \
    NeteasePlayer.cpp \
    AudioDecoder.cpp

HEADERS += \
    NeteasePlayer.h \
    AudioDecoder.h

# FFmpeg 头文件路径（GitHub Actions 中通过 apt 安装或 include/ 目录）
exists($$PWD/include/libavformat) {
    INCLUDEPATH += $$PWD/include
} else {
    # Ubuntu 上的标准路径
    INCLUDEPATH += /usr/include/x86_64-linux-gnu
    INCLUDEPATH += /usr/include
}

# FFmpeg 库路径（dictpen-libs 交叉编译库）
exists($$PWD/../dictpen-libs) {
    LIBS += -L$$PWD/../dictpen-libs
}
exists($$PWD/dictpen-libs) {
    LIBS += -L$$PWD/dictpen-libs
}

# 链接 FFmpeg 库（静态链接到插件中，避免运行时依赖）
LIBS += -lavformat -lavcodec -lavutil -lswresample \
        -lz -lm -ldl

# 编译选项
QMAKE_CXXFLAGS += -Wno-deprecated-declarations -Wno-unused-parameter
QMAKE_LFLAGS += -Wl,--as-needed

# 安装路径（打包时用）
target.path = /userdisk/PenMods/plugins/netease_music
INSTALLS += target
