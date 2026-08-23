#include "NeteasePlayer.h"
#include <QDebug>
#include <QAudioFormat>
#include <QAudioDeviceInfo>
#include <QProcess>
#include <QUrl>
#include <QJsonDocument>
#include <QJsonObject>

NeteasePlayer::NeteasePlayer(QObject *parent)
    : QObject(parent) {
    m_decoder = new AudioDecoder(this);
    connect(m_decoder, &AudioDecoder::audioReady, this, &NeteasePlayer::onAudioReady);
    connect(m_decoder, &AudioDecoder::positionChanged, this, &NeteasePlayer::onDecoderPosition);
    connect(m_decoder, &AudioDecoder::durationChanged, this, &NeteasePlayer::onDecoderDuration);
    connect(m_decoder, &AudioDecoder::finished, this, &NeteasePlayer::onDecoderFinished);
    connect(m_decoder, &AudioDecoder::errorOccurred, this, &NeteasePlayer::onDecoderError);

    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(250);
    connect(m_positionTimer, &QTimer::timeout, this, &NeteasePlayer::updatePositionTick);

    m_networkManager = new QNetworkAccessManager(this);
}

NeteasePlayer::~NeteasePlayer() {
    stop();
}

void NeteasePlayer::initAudioOutput() {
    cleanupAudio();
    QAudioFormat format;
    format.setSampleRate(OUT_SAMPLE_RATE);
    format.setChannelCount(OUT_CHANNELS);
    format.setSampleSize(16);
    format.setCodec("audio/pcm");
    format.setByteOrder(QAudioFormat::LittleEndian);
    format.setSampleType(QAudioFormat::SignedInt);

    QAudioDeviceInfo info = QAudioDeviceInfo::defaultOutputDevice();
    if (!info.isFormatSupported(format)) {
        qWarning() << "Audio format not supported, trying nearest";
        format = info.nearestFormat(format);
    }

    m_audioOutput = new QAudioOutput(format, this);
    m_audioOutput->setVolume(m_volume);
    connect(m_audioOutput, &QAudioOutput::stateChanged, this, &NeteasePlayer::onAudioStateChanged);
    m_audioBuf = m_audioOutput->start();
}

void NeteasePlayer::cleanupAudio() {
    if (m_audioOutput) {
        m_audioOutput->stop();
        m_audioOutput->deleteLater();
        m_audioOutput = nullptr;
    }
    m_audioBuf = nullptr;
}

void NeteasePlayer::play(const QString &source) {
    qDebug() << "[NeteasePlayer] play called, source:" << source;
    if (source.isEmpty()) {
        qWarning() << "[NeteasePlayer] source is empty, return";
        return;
    }
    stop();

    m_source = source;
    emit sourceChanged(source);
    m_errorString.clear();

    // 如果是网络 URL，先通过 Go server 下载缓存到本地，再播放本地文件
    // FFmpeg 直接播放 HTTP 流有问题（Invalid data found when processing input）
    if (source.startsWith("http://") || source.startsWith("https://")) {
        QUrl qurl(source);
        QByteArray encoded = qurl.toEncoded(QUrl::FullyEncoded);
        QString cacheUrl = QString("http://127.0.0.1:8001/cache?url=%1").arg(QString::fromUtf8(encoded));
        qDebug() << "[NeteasePlayer] requesting cache:" << cacheUrl;

        QUrl reqUrl(cacheUrl);
        QNetworkRequest request(reqUrl);
        m_cacheReply = m_networkManager->get(request);
        connect(m_cacheReply, &QNetworkReply::finished, this, &NeteasePlayer::onCacheReply);
        return;
    }

    // 本地文件直接播放
    startPlayback(source);
}

void NeteasePlayer::onCacheReply() {
    if (!m_cacheReply) return;
    QNetworkReply *reply = m_cacheReply;
    m_cacheReply = nullptr;

    if (reply->error() != QNetworkReply::NoError) {
        m_errorString = "缓存下载失败: " + reply->errorString();
        qWarning() << "[NeteasePlayer] cache request failed:" << reply->errorString();
        emit errorOccurred(m_errorString);
        reply->deleteLater();
        return;
    }

    QByteArray data = reply->readAll();
    reply->deleteLater();

    // 解析 JSON 响应，获取本地文件路径
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (doc.isNull() || !doc.isObject()) {
        m_errorString = "缓存响应解析失败";
        qWarning() << "[NeteasePlayer] cache response parse failed:" << data;
        emit errorOccurred(m_errorString);
        return;
    }

    QJsonObject obj = doc.object();
    if (obj.value("code").toInt() != 200) {
        m_errorString = "缓存下载失败: " + obj.value("msg").toString();
        qWarning() << "[NeteasePlayer] cache error:" << data;
        emit errorOccurred(m_errorString);
        return;
    }

    QString localPath = obj.value("path").toString();
    bool cached = obj.value("cached").toBool();
    qDebug() << "[NeteasePlayer] cache ready, local path:" << localPath << "cached:" << cached;

    if (localPath.isEmpty()) {
        m_errorString = "缓存路径为空";
        emit errorOccurred(m_errorString);
        return;
    }

    // 播放本地缓存文件
    startPlayback(localPath);
}

void NeteasePlayer::startPlayback(const QString &source) {
    qDebug() << "[NeteasePlayer] startPlayback, source:" << source;

    qDebug() << "[NeteasePlayer] initAudioOutput...";
    initAudioOutput();
    if (!m_audioOutput || !m_audioBuf) {
        m_errorString = "无法初始化音频输出";
        qWarning() << "[NeteasePlayer] audio output init failed!";
        emit errorOccurred(m_errorString);
        return;
    }
    qDebug() << "[NeteasePlayer] audio output init success, volume:" << m_volume;

    m_position = 0;
    m_duration = 0;
    setPaused(false);
    setPlaying(true);
    m_positionTimer->start();
    qDebug() << "[NeteasePlayer] starting decoder...";
    m_decoder->start(source);
}

void NeteasePlayer::pause() {
    if (!m_playing || m_paused) return;
    m_paused = true;
    m_decoder->setPaused(true);
    if (m_audioOutput) {
        m_audioOutput->suspend();
    }
    emit pausedChanged(true);
}

void NeteasePlayer::resume() {
    if (!m_playing || !m_paused) return;
    m_paused = false;
    m_decoder->setPaused(false);
    if (m_audioOutput) {
        m_audioOutput->resume();
    }
    emit pausedChanged(false);
}

void NeteasePlayer::togglePause() {
    if (m_paused) resume();
    else pause();
}

void NeteasePlayer::stop() {
    m_positionTimer->stop();
    if (m_decoder) {
        m_decoder->stop();
    }
    cleanupAudio();
    if (m_playing) {
        setPlaying(false);
    }
    if (m_paused) {
        m_paused = false;
        emit pausedChanged(false);
    }
    m_position = 0;
    emit positionChanged(0);
}

void NeteasePlayer::seek(qint64 ms) {
    if (!m_playing) return;
    if (ms < 0) ms = 0;
    if (m_duration > 0 && ms > m_duration) ms = m_duration;
    m_seeking = true;
    m_position = ms;
    emit positionChanged(ms);
    m_decoder->seek(ms);
    // seek 后清空音频缓冲区，避免旧数据
    if (m_audioOutput) {
        m_audioOutput->reset();
        m_audioBuf = m_audioOutput->start();
    }
    QTimer::singleShot(300, [this] { m_seeking = false; });
}

void NeteasePlayer::setVolume(qreal v) {
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    m_volume = v;
    if (m_audioOutput) {
        m_audioOutput->setVolume(v);
    }
    emit volumeChanged(v);
}

void NeteasePlayer::onAudioReady(const QByteArray &pcm) {
    if (!m_audioBuf || m_paused || m_seeking) return;
    // 写入音频缓冲区，QAudioOutput 会自动播放
    qint64 written = m_audioBuf->write(pcm);
    static int pcmCount = 0;
    if (pcmCount++ % 50 == 0) {
        qDebug() << "[NeteasePlayer] onAudioReady, pcm size:" << pcm.size() << "written:" << written << "count:" << pcmCount;
    }
}

void NeteasePlayer::onDecoderPosition(qint64 ms) {
    if (m_seeking) return;
    m_position = ms;
    emit positionChanged(ms);
}

void NeteasePlayer::onDecoderDuration(qint64 ms) {
    m_duration = ms;
    emit durationChanged(ms);
}

void NeteasePlayer::onDecoderFinished() {
    // 等待音频缓冲区播放完毕
    QTimer::singleShot(500, [this] {
        setPlaying(false);
        setPaused(false);
        m_position = m_duration > 0 ? m_duration : 0;
        emit positionChanged(m_position);
        cleanupAudio();
        emit finished();
    });
}

void NeteasePlayer::onDecoderError(const QString &msg) {
    qWarning() << "[NeteasePlayer] decoder error:" << msg;
    m_errorString = msg;
    emit errorOccurred(msg);
    stop();
}

void NeteasePlayer::onAudioStateChanged(QAudio::State state) {
    qDebug() << "[NeteasePlayer] audio state changed:" << state;
    if (state == QAudio::StoppedState && m_audioOutput) {
        QAudio::Error err = m_audioOutput->error();
        if (err != QAudio::NoError && m_playing) {
            qWarning() << "[NeteasePlayer] Audio output error:" << err;
        }
    }
}

void NeteasePlayer::updatePositionTick() {
    // 备用位置更新：如果解码器没发信号，用 QAudioOutput 的 processedUSecs
    if (!m_audioOutput || m_paused || m_seeking) return;
    qint64 processedMs = m_audioOutput->processedUSecs() / 1000;
    // 只在解码器位置更新不及时时用这个
    // （解码器的 positionChanged 更准确，这里只是兜底）
}

void NeteasePlayer::setPlaying(bool p) {
    if (m_playing != p) {
        m_playing = p;
        emit playingChanged(p);
    }
}

void NeteasePlayer::setPaused(bool p) {
    if (m_paused != p) {
        m_paused = p;
        emit pausedChanged(p);
    }
}

void NeteasePlayer::startServer(const QString &path) {
    if (path.isEmpty()) return;
    // 先杀掉旧进程
    QProcess::execute("pkill", QStringList() << "-f" << path);
    // 确保有执行权限
    QProcess::execute("chmod", QStringList() << "+x" << path);
    // 火忘式启动
    QProcess::startDetached(path, QStringList());
    qInfo() << "Started server:" << path;
}

void NeteasePlayer::execDetached(const QString &cmd) {
    if (cmd.isEmpty()) return;
    QProcess::startDetached("sh", QStringList() << "-c" << cmd);
}
