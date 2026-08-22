#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include "NeteasePlayer.h"

class NeteasePlayerPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlExtensionInterface")
public:
    void registerTypes(const char *uri) override {
        qmlRegisterType<NeteasePlayer>(uri, 1, 0, "NeteasePlayer");
    }
};

#include "plugin.moc"
