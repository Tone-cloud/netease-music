# NeteasePlayer - 词典笔网易云音乐播放器插件
# 仅桥接 PenMods 系统播放器，QML 类型 NeteasePlayer

QT       += core network
CONFIG   += shared c++11
TEMPLATE = lib
TARGET   = netease_player

# 编译产物：libnetease_player.so
DESTDIR = $$PWD/../build

SOURCES += \
    plugin.cpp \
    NeteasePlayer.cpp

HEADERS += \
    NeteasePlayer.h

# QtQml 手动包含（QT += qml 模块检测在交叉编译时可能失败）
# 用相对路径，因为 Qt 编译目录在项目根目录下
INCLUDEPATH += $$PWD/../qt-5.15.2-for-aarch64-dictpen-linux/include/QtQml
INCLUDEPATH += $$PWD/../qt-5.15.2-for-aarch64-dictpen-linux/include/QtQml/5.15.2
INCLUDEPATH += $$PWD/../qt-5.15.2-for-aarch64-dictpen-linux/include

# Qt and PenMods device libraries used by the cross linker
LIBS += -L$$PWD/../qt-5.15.2-for-aarch64-dictpen-linux/lib
exists($$PWD/../dictpen-libs) {
    LIBS += -L$$PWD/../dictpen-libs
}
LIBS += -lQt5Qml -lGLESv2 -lEGL -lmali

# 编译选项
QMAKE_CXXFLAGS += -Wno-deprecated-declarations -Wno-unused-parameter
QMAKE_LFLAGS += -Wl,--as-needed

# 安装路径（打包时用）
target.path = /userdisk/PenMods/plugins/netease_music
INSTALLS += target
