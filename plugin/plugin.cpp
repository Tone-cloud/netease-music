// PenMods 插件入口
// PenMods 通过 QLibrary 手动加载 .so，要求导出 init_plugin()
// 可选 attach_engine(QQmlEngine*) 用于注册 QML 类型

#include <QQmlEngine>
#include <QDebug>
extern "C" {
#include <libavformat/avformat.h>
}
#include "NeteasePlayer.h"

extern "C" {

// 必须导出：PenMods 加载后首先调用
void init_plugin() {
    qDebug() << "[NeteasePlugin] init_plugin called, avformat_network_init...";
    avformat_network_init();
    qDebug() << "[NeteasePlugin] init_plugin done";
}

// 可选导出：QML 引擎就绪后调用，用于注册自定义 QML 类型
void attach_engine(QQmlEngine* engine) {
    Q_UNUSED(engine);
    qDebug() << "[NeteasePlugin] attach_engine, registering NeteasePlayer type";
    qmlRegisterType<NeteasePlayer>("NeteasePlayer", 1, 0, "NeteasePlayer");
}

} // extern "C"
