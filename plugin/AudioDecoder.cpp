#include "AudioDecoder.h"
#include <QDebug>

AudioDecoder::AudioDecoder(QObject *parent)
    : QObject(parent) {
    // 初始化 FFmpeg 网络协议（只调用一次）
    static bool networkInited = false;
    if (!networkInited) {
        avformat_network_init();
        networkInited = true;
        qDebug() << "[AudioDecoder] avformat_network_init done";
    }
}

AudioDecoder::~AudioDecoder() {
    stop();
}

void AudioDecoder::start(const QString &path) {
    qDebug() << "[AudioDecoder] start called, path:" << path;
    stop();
    m_path = path;
    m_stop.store(false);
    m_pause.store(false);
    m_seeking.store(false);
    m_thread = std::thread(&AudioDecoder::decodeLoop, this);
}

void AudioDecoder::stop() {
    m_stop.store(true);
    m_pause.store(false);
    m_cond.notify_all();
    if (m_thread.joinable()) {
        m_thread.join();
    }
    cleanup();
}

void AudioDecoder::seek(qint64 ms) {
    m_seekTarget.store(ms);
    m_seeking.store(true);
    m_cond.notify_all();
}

void AudioDecoder::setPaused(bool paused) {
    m_pause.store(paused);
    if (!paused) {
        m_cond.notify_all();
    }
}

void AudioDecoder::cleanup() {
    if (m_resampleBuf) {
        av_freep(&m_resampleBuf);
        m_resampleBuf = nullptr;
    }
    m_resampleBufSize = 0;
    if (m_swrCtx) {
        swr_free(&m_swrCtx);
        m_swrCtx = nullptr;
    }
    if (m_codecCtx) {
        avcodec_free_context(&m_codecCtx);
        m_codecCtx = nullptr;
    }
    if (m_fmtCtx) {
        avformat_close_input(&m_fmtCtx);
        m_fmtCtx = nullptr;
    }
    m_audioStreamIndex = -1;
}

bool AudioDecoder::openInput() {
    QByteArray pathBytes = m_path.toUtf8();
    int ret = avformat_open_input(&m_fmtCtx, pathBytes.constData(), nullptr, nullptr);
    if (ret < 0) {
        char errbuf[256];
        av_strerror(ret, errbuf, sizeof(errbuf));
        emit errorOccurred(QString("无法打开: %1").arg(errbuf));
        return false;
    }
    ret = avformat_find_stream_info(m_fmtCtx, nullptr);
    if (ret < 0) {
        emit errorOccurred("无法获取流信息");
        return false;
    }
    // 时长
    if (m_fmtCtx->duration != AV_NOPTS_VALUE) {
        qint64 durMs = (m_fmtCtx->duration * 1000) / AV_TIME_BASE;
        m_durationMs.store(durMs);
        emit durationChanged(durMs);
    }
    return true;
}

bool AudioDecoder::initDecoder() {
    // 找音频流
    m_audioStreamIndex = av_find_best_stream(m_fmtCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    if (m_audioStreamIndex < 0) {
        emit errorOccurred("未找到音频流");
        return false;
    }
    AVStream *stream = m_fmtCtx->streams[m_audioStreamIndex];
    m_timeBase = stream->time_base;

    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        emit errorOccurred("不支持的音频编码");
        return false;
    }
    m_codecCtx = avcodec_alloc_context3(codec);
    if (!m_codecCtx) {
        emit errorOccurred("分配解码器失败");
        return false;
    }
    avcodec_parameters_to_context(m_codecCtx, stream->codecpar);
    if (avcodec_open2(m_codecCtx, codec, nullptr) < 0) {
        emit errorOccurred("打开解码器失败");
        return false;
    }

    // 重采样：转为 44100Hz 立体声 S16
    m_swrCtx = swr_alloc_set_opts(
        nullptr,
        av_get_default_channel_layout(OUT_CHANNELS),
        OUT_SAMPLE_FMT,
        OUT_SAMPLE_RATE,
        m_codecCtx->channel_layout ? m_codecCtx->channel_layout
                                    : av_get_default_channel_layout(m_codecCtx->channels),
        m_codecCtx->sample_fmt,
        m_codecCtx->sample_rate,
        0, nullptr);
    if (!m_swrCtx || swr_init(m_swrCtx) < 0) {
        emit errorOccurred("初始化重采样失败");
        return false;
    }
    return true;
}

void AudioDecoder::decodeLoop() {
    qDebug() << "[AudioDecoder] decodeLoop started";
    if (!openInput() || !initDecoder()) {
        qWarning() << "[AudioDecoder] openInput or initDecoder failed!";
        cleanup();
        return;
    }
    qDebug() << "[AudioDecoder] init success, starting decode";

    AVPacket *pkt = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    qint64 lastPosEmit = 0;
    int frameCount = 0;

    while (!m_stop.load()) {
        // 暂停处理
        if (m_pause.load()) {
            std::unique_lock<std::mutex> lock(m_mutex);
            m_cond.wait_for(lock, std::chrono::milliseconds(100),
                            [this] { return !m_pause.load() || m_stop.load(); });
            continue;
        }

        // seek 处理
        if (m_seeking.load()) {
            qint64 target = m_seekTarget.load();
            qint64 targetTs = (target * AV_TIME_BASE) / 1000;
            av_seek_frame(m_fmtCtx, -1, targetTs, AVSEEK_FLAG_BACKWARD);
            avcodec_flush_buffers(m_codecCtx);
            m_seeking.store(false);
            m_positionMs.store(target);
        }

        int ret = av_read_frame(m_fmtCtx, pkt);
        if (ret < 0) {
            if (ret == AVERROR_EOF) {
                // 播放结束
                emit finished();
            }
            break;
        }

        if (pkt->stream_index != m_audioStreamIndex) {
            av_packet_unref(pkt);
            continue;
        }

        ret = avcodec_send_packet(m_codecCtx, pkt);
        av_packet_unref(pkt);
        if (ret < 0) continue;

        while (ret >= 0) {
            ret = avcodec_receive_frame(m_codecCtx, frame);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) break;
            if (ret < 0) continue;

            // 更新位置
            if (frame->pts != AV_NOPTS_VALUE) {
                qint64 posMs = (frame->pts * 1000 * m_timeBase.num) / m_timeBase.den;
                m_positionMs.store(posMs);
                if (posMs - lastPosEmit >= 200) {
                    emit positionChanged(posMs);
                    lastPosEmit = posMs;
                }
            }

            // 重采样
            int outSamples = swr_get_out_samples(m_swrCtx, frame->nb_samples);
            if (outSamples > m_resampleBufSize) {
                if (m_resampleBuf) av_freep(&m_resampleBuf);
                av_samples_alloc(&m_resampleBuf, nullptr, OUT_CHANNELS,
                                 outSamples, OUT_SAMPLE_FMT, 0);
                m_resampleBufSize = outSamples;
            }
            int converted = swr_convert(m_swrCtx, &m_resampleBuf, outSamples,
                                         (const uint8_t **)frame->data, frame->nb_samples);
            if (converted > 0) {
                int dataSize = converted * OUT_CHANNELS * av_get_bytes_per_sample(OUT_SAMPLE_FMT);
                QByteArray pcm(reinterpret_cast<const char *>(m_resampleBuf), dataSize);
                emit audioReady(pcm);
                frameCount++;
                if (frameCount % 50 == 0) {
                    qDebug() << "[AudioDecoder] decoded" << frameCount << "frames, last pcm size:" << dataSize;
                }
            }
            av_frame_unref(frame);
        }
    }

    qDebug() << "[AudioDecoder] decode loop ended, total frames:" << frameCount;
    av_frame_free(&frame);
    av_packet_free(&pkt);
    cleanup();
}
