# NeteasePlayer - 词典笔网易云音乐播放器插件
# FFmpeg 解码 + QAudioOutput 播放，QML 类型 NeteasePlayer

QT       += core multimedia
CONFIG   += shared c++11
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

# QtQml 手动包含（QT += qml 模块检测在交叉编译时可能失败）
# 用相对路径，因为 Qt 编译目录在项目根目录下
INCLUDEPATH += $$PWD/../qt-5.15.2-for-aarch64-dictpen-linux/include/QtQml
INCLUDEPATH += $$PWD/../qt-5.15.2-for-aarch64-dictpen-linux/include/QtQml/5.15.2
INCLUDEPATH += $$PWD/../qt-5.15.2-for-aarch64-dictpen-linux/include
LIBS += -lQt5Qml

# FFmpeg 头文件路径（已从主机复制到 plugin/include/，平台无关）
# 注意：不能加 /usr/include/x86_64-linux-gnu 等主机路径，
# 否则交叉编译器会包含 x86 特定的 gnu/stubs.h 导致编译失败
INCLUDEPATH += $$PWD/include

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
