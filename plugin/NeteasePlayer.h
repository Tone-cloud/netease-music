#pragma once
#include <QObject>
#include <QString>
#include <QByteArray>
#include <QAudio>
#include <QAudioOutput>
#include <QTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include "AudioDecoder.h"

/**
 * @brief 网易云音乐播放器 QML 类型
 *
 * 封装 FFmpeg 解码 + QAudioOutput 播放，提供 QML 友好的 API。
 * 支持本地文件和 HTTP URL，支持播放/暂停/停止/跳转/音量。
 *
 * QML 用法：
 *   NeteasePlayer {
 *       id: player
 *       onPositionChanged: progressBar.value = position
 *       onFinished: playNext()
 *   }
 *   player.play("http://example.com/song.mp3")
 */
class NeteasePlayer : public QObject {
    Q_OBJECT
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool playing READ isPlaying NOTIFY playingChanged)
    Q_PROPERTY(bool paused READ isPaused NOTIFY pausedChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(QString source READ source NOTIFY sourceChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorOccurred)

public:
    explicit NeteasePlayer(QObject *parent = nullptr);
    ~NeteasePlayer() override;

    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    bool isPlaying() const { return m_playing; }
    bool isPaused() const { return m_paused; }
    qreal volume() const { return m_volume; }
    QString source() const { return m_source; }
    QString errorString() const { return m_errorString; }

public slots:
    /// 播放指定源（本地路径或 HTTP URL）
    void play(const QString &source);
    /// 暂停
    void pause();
    /// 从暂停恢复
    void resume();
    /// 暂停/恢复切换
    void togglePause();
    /// 停止
    void stop();
    /// 跳转到指定位置（毫秒）
    void seek(qint64 ms);
    /// 设置音量（0.0 - 1.0）
    void setVolume(qreal v);
    /// 启动 Go server（QProcess 火忘式）
    Q_INVOKABLE void startServer(const QString &path);
    /// 执行 shell 命令（火忘式，用于启动 server 等）
    Q_INVOKABLE void execDetached(const QString &cmd);

signals:
    void positionChanged(qint64 ms);
    void durationChanged(qint64 ms);
    void playingChanged(bool playing);
    void pausedChanged(bool paused);
    void volumeChanged(qreal v);
    void sourceChanged(const QString &source);
    void finished();
    void errorOccurred(const QString &message);

private slots:
    void onAudioReady(const QByteArray &pcm);
    void onDecoderPosition(qint64 ms);
    void onDecoderDuration(qint64 ms);
    void onDecoderFinished();
    void onDecoderError(const QString &msg);
    void onAudioStateChanged(QAudio::State state);
    void updatePositionTick();
    void onCacheReply();

private:
    void initAudioOutput();
    void cleanupAudio();
    void setPlaying(bool p);
    void setPaused(bool p);
    void startPlayback(const QString &source);  // 实际开始播放（本地文件）

    AudioDecoder *m_decoder = nullptr;
    QAudioOutput *m_audioOutput = nullptr;
    QIODevice *m_audioBuf = nullptr;  // QAudioOutput 推模式缓冲区
    QTimer *m_positionTimer = nullptr;
    QNetworkAccessManager *m_networkManager = nullptr;
    QNetworkReply *m_cacheReply = nullptr;

    QString m_source;
    QString m_errorString;
    qint64 m_position = 0;
    qint64 m_duration = 0;
    qreal m_volume = 1.0;
    bool m_playing = false;
    bool m_paused = false;
    bool m_seeking = false;
};
