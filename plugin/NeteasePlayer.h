#pragma once
#include <QObject>
#include <QString>
#include <QByteArray>
#include <QTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>

// 有道词典笔系统原生播放器相关结构体（参考 PenMods）
struct YMediaEntity {
    char    unk[10];
    QString mMediaId;
    QString mOwnerId;
    QString mTitle;
    int     mDuration;
    int     mDownloadState;
    QString mUrl;
    QString mLocalFile;
    QString mLrcFile;
    int     mLrcState;
    bool    mSrcAudioVisible;
};

struct YColumnMediaEntity : public YMediaEntity {
    int     mId;
    QString mColumnId;
    int     mProgress;
    bool    mIsDir;
};

/**
 * @brief 网易云音乐播放器 QML 类型
 *
 * 仅桥接 PenMods 系统播放器，负责缓存 URL 解析和播放调度。
 * 支持本地文件和 HTTP URL，并在需要时通过 Go server 缓存后交给系统播放器播放。
 */
class NeteasePlayer : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString source READ source NOTIFY sourceChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorOccurred)

public:
    explicit NeteasePlayer(QObject *parent = nullptr);
    ~NeteasePlayer() override;

    QString source() const { return m_source; }
    QString errorString() const { return m_errorString; }

public slots:
    /// 播放指定源（本地路径或 HTTP URL）
    void play(const QString &source);
    /// 停止
    void stop();
    /// 启动 Go server（QProcess 火忘式）
    Q_INVOKABLE void startServer(const QString &path);
    /// 执行 shell 命令（火忘式，用于启动 server 等）
    Q_INVOKABLE void execDetached(const QString &cmd);
    /// 使用系统原生播放器播放本地文件
    Q_INVOKABLE void playWithSystemPlayer(const QString &filePath);

signals:
    void sourceChanged(const QString &source);
    void finished();
    void errorOccurred(const QString &message);

private slots:
    void onCacheReply();
    void checkSystemPlayerState();  // 轮询系统播放器状态，检测播放完成

private:
    void setPlaying(bool p);

    QNetworkAccessManager *m_networkManager = nullptr;
    QNetworkReply *m_cacheReply = nullptr;
    QTimer *m_systemPlayerTimer = nullptr;  // 系统播放器状态轮询
    bool m_usingSystemPlayer = false;       // 是否使用系统播放器
    bool m_playing = false;

    QString m_source;
    QString m_errorString;
};
