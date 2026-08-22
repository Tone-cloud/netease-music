#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include "NeteasePlayer.h"

class NeteasePlayerPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        Q_ASSERT(uri == QLatin1String("NeteasePlayer"));
        qmlRegisterType<NeteasePlayer>(uri, 1, 0, "NeteasePlayer");
    }
};

#include "plugin.moc"
