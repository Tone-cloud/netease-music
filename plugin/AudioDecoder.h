#pragma once
#include <QObject>
#include <QString>
#include <QByteArray>
#include <atomic>
#include <memory>
#include <thread>
#include <mutex>
#include <condition_variable>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
}

// 输出格式：44100Hz 立体声 S16（词典笔 ALSA 兼容）
static const int OUT_SAMPLE_RATE = 44100;
static const int OUT_CHANNELS = 2;
static const AVSampleFormat OUT_SAMPLE_FMT = AV_SAMPLE_FMT_S16;

/**
 * @brief FFmpeg 音频解码器
 *
 * 负责打开音频源（本地文件或 HTTP URL），解码并重采样为
 * 44100Hz 立体声 S16 PCM，通过 audioReady 信号输出。
 * 运行在独立线程，支持 seek / pause / stop。
 */
class AudioDecoder : public QObject {
    Q_OBJECT
public:
    explicit AudioDecoder(QObject *parent = nullptr);
    ~AudioDecoder() override;

    void start(const QString &path);
    void stop();
    void seek(qint64 ms);
    void setPaused(bool paused);
    bool isPaused() const { return m_pause.load(); }
    qint64 duration() const { return m_durationMs.load(); }

signals:
    void audioReady(const QByteArray &pcm);   // 解码出的 PCM 数据
    void durationChanged(qint64 ms);           // 总时长（毫秒）
    void positionChanged(qint64 ms);           // 当前播放位置（毫秒）
    void finished();                             // 播放结束
    void errorOccurred(const QString &message);

private:
    void decodeLoop();
    bool openInput();
    bool initDecoder();
    void cleanup();

    // 线程与同步
    std::thread m_thread;
    std::atomic<bool> m_stop{false};
    std::atomic<bool> m_pause{false};
    std::atomic<bool> m_seeking{false};
    std::atomic<qint64> m_seekTarget{0};
    std::atomic<qint64> m_durationMs{0};
    std::atomic<qint64> m_positionMs{0};
    std::mutex m_mutex;
    std::condition_variable m_cond;

    // FFmpeg 上下文
    AVFormatContext *m_fmtCtx = nullptr;
    AVCodecContext *m_codecCtx = nullptr;
    SwrContext *m_swrCtx = nullptr;
    int m_audioStreamIndex = -1;
    AVRational m_timeBase{};

    // 重采样输出缓冲
    uint8_t *m_resampleBuf = nullptr;
    int m_resampleBufSize = 0;

    QString m_path;
};
