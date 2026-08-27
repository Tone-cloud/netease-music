#include "NeteasePlayer.h"
#include <QDebug>
#include <QAudioFormat>
#include <QAudioDeviceInfo>
#include <QProcess>
#include <QUrl>
#include <QJsonDocument>
#include <QJsonObject>
#include <dlfcn.h>
#include <QFileInfo>

#include <elf.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>

// ========== ELF .symtab 符号解析器 ==========
// dlsym 只能查 .dynsym（动态符号表），有道主程序的 C++ 符号在 .symtab（静态符号表）中，
// 没有被导出，所以需要自己解析 ELF 文件查找符号地址。

/// 获取主程序路径
static QString getExePath() {
    char exePath[512];
    ssize_t len = readlink("/proc/self/exe", exePath, sizeof(exePath) - 1);
    if (len <= 0) return QString();
    exePath[len] = '\0';
    return QString::fromLocal8Bit(exePath);
}

/// 从 /proc/self/maps 获取主程序加载基地址（按主程序路径查找，和 PenMods 一致）
static quint64 getMainBase() {
    QString exePath = getExePath();
    if (exePath.isEmpty()) return 0;
    QByteArray exeBa = exePath.toLocal8Bit();
    const char *exeName = exeBa.constData();

    FILE *f = fopen("/proc/self/maps", "r");
    if (!f) return 0;
    char line[1024];
    quint64 base = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, exeName)) {
            char *p = strtok(line, "-");
            base = strtoul(p, nullptr, 16);
            if (base == 0x8000) base = 0;
            break;
        }
    }
    fclose(f);
    qDebug() << "[resolveSymbol] exe:" << exePath << "base:" << (void*)base;
    return base;
}

/// 解析主程序 ELF 的 .symtab 段，按符号名查找地址
static void *resolveSymbol(const char *name) {
    static quint64 base = 0;
    static bool baseInited = false;
    if (!baseInited) {
        base = getMainBase();
        baseInited = true;
    }
    if (!base || !name) return nullptr;

    QString exePath = getExePath();
    if (exePath.isEmpty()) return nullptr;
    QByteArray exeBa = exePath.toLocal8Bit();

    int fd = open(exeBa.constData(), O_RDONLY);
    if (fd < 0) {
        qWarning() << "[resolveSymbol] open failed:" << exePath;
        return nullptr;
    }

    // 读取 ELF header
    Elf64_Ehdr ehdr;
    memset(&ehdr, 0, sizeof(ehdr));
    ssize_t r = read(fd, &ehdr, sizeof(ehdr));
    if (r != (ssize_t)sizeof(ehdr)) {
        qWarning() << "[resolveSymbol] read ehdr failed, got" << r;
        close(fd);
        return nullptr;
    }
    if (memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0) {
        qWarning() << "[resolveSymbol] not an ELF file";
        close(fd);
        return nullptr;
    }
    qDebug() << "[resolveSymbol] ELF shnum=" << ehdr.e_shnum << "shoff=" << (void*)ehdr.e_shoff;

    if (ehdr.e_shnum == 0 || ehdr.e_shoff == 0) {
        qWarning() << "[resolveSymbol] no section headers";
        close(fd);
        return nullptr;
    }

    // 读取 section header table
    size_t shdrSize = sizeof(Elf64_Shdr) * ehdr.e_shnum;
    Elf64_Shdr *shdrs = (Elf64_Shdr*)malloc(shdrSize);
    if (!shdrs) {
        qWarning() << "[resolveSymbol] malloc shdrs failed, size" << shdrSize;
        close(fd);
        return nullptr;
    }
    memset(shdrs, 0, shdrSize);
    lseek(fd, ehdr.e_shoff, SEEK_SET);
    r = read(fd, shdrs, shdrSize);
    if (r != (ssize_t)shdrSize) {
        qWarning() << "[resolveSymbol] read shdrs failed, got" << r << "expected" << shdrSize;
        free(shdrs);
        close(fd);
        return nullptr;
    }

    // 找到 .symtab 段和对应的 .strtab 字符串表
    Elf64_Shdr *symtabSec = nullptr;
    Elf64_Shdr *strtabSec = nullptr;
    for (int i = 0; i < (int)ehdr.e_shnum; i++) {
        if (shdrs[i].sh_type == SHT_SYMTAB) {
            symtabSec = &shdrs[i];
            if (symtabSec->sh_link < ehdr.e_shnum) {
                strtabSec = &shdrs[symtabSec->sh_link];
            }
            break;
        }
    }
    if (!symtabSec || !strtabSec) {
        qWarning() << "[resolveSymbol] .symtab not found";
        free(shdrs);
        close(fd);
        return nullptr;
    }
    qDebug() << "[resolveSymbol] symtab size=" << symtabSec->sh_size
             << "strtab size=" << strtabSec->sh_size;

    // 读取字符串表
    char *strs = (char*)malloc(strtabSec->sh_size > 0 ? strtabSec->sh_size : 1);
    if (!strs) {
        qWarning() << "[resolveSymbol] malloc strs failed";
        free(shdrs);
        close(fd);
        return nullptr;
    }
    memset(strs, 0, strtabSec->sh_size > 0 ? strtabSec->sh_size : 1);
    lseek(fd, strtabSec->sh_offset, SEEK_SET);
    read(fd, strs, strtabSec->sh_size);

    // 读取符号表
    int symCount = strtabSec->sh_size > 0 ? (int)(symtabSec->sh_size / sizeof(Elf64_Sym)) : 0;
    Elf64_Sym *syms = (Elf64_Sym*)malloc(symCount > 0 ? sizeof(Elf64_Sym) * symCount : 1);
    if (!syms) {
        qWarning() << "[resolveSymbol] malloc syms failed, count" << symCount;
        free(strs);
        free(shdrs);
        close(fd);
        return nullptr;
    }
    memset(syms, 0, symCount > 0 ? sizeof(Elf64_Sym) * symCount : 1);
    lseek(fd, symtabSec->sh_offset, SEEK_SET);
    read(fd, syms, symtabSec->sh_size);

    qDebug() << "[resolveSymbol] searching for" << name << "among" << symCount << "symbols";

    // 查找符号
    void *result = nullptr;
    for (int i = 0; i < symCount; i++) {
        if (syms[i].st_name >= strtabSec->sh_size) continue;
        const char *symName = strs + syms[i].st_name;
        if (!symName) continue;
        if (strcmp(symName, name) == 0 && syms[i].st_value != 0) {
            result = reinterpret_cast<void*>(syms[i].st_value);  // PenMods 不加 base，直接用 st_value
            qDebug() << "[resolveSymbol] found" << name << "->" << result
                     << "(st_value=" << (void*)syms[i].st_value << "base=" << (void*)base << ")";
            break;
        }
    }

    if (!result) {
        qWarning() << "[resolveSymbol] symbol not found:" << name;
    }

    free(syms);
    free(strs);
    free(shdrs);
    close(fd);
    return result;
}

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

    // 使用系统原生播放器播放本地缓存文件
    playWithSystemPlayer(localPath);
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

void NeteasePlayer::playWithSystemPlayer(const QString &filePath) {
    qDebug() << "[NeteasePlayer] playWithSystemPlayer (PenMods style), file:" << filePath;

    if (filePath.isEmpty()) {
        emit errorOccurred("文件路径为空");
        return;
    }

    QFileInfo fi(filePath);
    if (!fi.exists()) {
        emit errorOccurred("文件不存在: " + filePath);
        return;
    }

    // ========== 函数指针类型定义（完全对齐 PenMods） ==========
    typedef void* (*InstanceFunc)();
    typedef void  (*CtorFunc)(void*, void*);
    typedef void* (*PlayAudioFunc)(void*, YColumnMediaEntity*, bool);
    typedef void* (*ShowPlayerFunc)(void*);
    typedef void  (*WipeDataFunc)(void*);
    typedef bool  (*SetColumnFunc)(void*, const QString&);
    typedef void  (*OnClickedPlayFunc)(void*);
    typedef int   (*PlayStateFunc)(void*);

    // ========== 获取所有系统符号（通过 ELF .symtab 解析） ==========
    InstanceFunc mediaManagerInstance = (InstanceFunc)resolveSymbol("_ZN10YSingletonI13YMediaManagerE8instanceEv");
    InstanceFunc mpmInstance = (InstanceFunc)resolveSymbol("_ZN10YSingletonI19YMediaPlayerManagerE8instanceEv");
    CtorFunc entityCtor = (CtorFunc)resolveSymbol("_ZN18YColumnMediaEntityC2EP7QObject");
    PlayAudioFunc playAudio = (PlayAudioFunc)resolveSymbol("_ZN13YMediaManager9playAudioERK18YColumnMediaEntityb");
    WipeDataFunc wipeData = (WipeDataFunc)resolveSymbol("_ZN19YMediaPlayerManager8wipeDataEv");
    SetColumnFunc setColumn = (SetColumnFunc)resolveSymbol("_ZN7YGlobal23setAudioPlayingColomnIdERK7QString");
    InstanceFunc globalInstance = (InstanceFunc)resolveSymbol("_ZN10YSingletonI7YGlobalE8instanceEv");
    ShowPlayerFunc showPlayer = (ShowPlayerFunc)resolveSymbol("_ZN7YGlobal15showAudioPlayerEv");
    OnClickedPlayFunc onClickedPlay = (OnClickedPlayFunc)resolveSymbol("_ZN19YMediaPlayerManager13onClickedPlayEv");
    PlayStateFunc playState = (PlayStateFunc)resolveSymbol("_ZNK19YMediaPlayerManager9playStateEv");

    qDebug() << "[NeteasePlayer] symbols:"
             << "mediaMgrInst=" << (void*)mediaManagerInstance
             << "mpmInst=" << (void*)mpmInstance
             << "entityCtor=" << (void*)entityCtor
             << "playAudio=" << (void*)playAudio
             << "wipeData=" << (void*)wipeData
             << "setColumn=" << (void*)setColumn
             << "globalInst=" << (void*)globalInstance
             << "showPlayer=" << (void*)showPlayer
             << "onClickedPlay=" << (void*)onClickedPlay
             << "playState=" << (void*)playState;

    if (!mediaManagerInstance || !entityCtor || !playAudio) {
        emit errorOccurred("缺少核心符号: mediaManager/entityCtor/playAudio");
        return;
    }

    // ========== Step 1: 获取单例（用 instance() 方法，安全） ==========
    qDebug() << "[NeteasePlayer] step1: get instances...";
    void* mediaManager = mediaManagerInstance();
    void* mpm = mpmInstance ? mpmInstance() : nullptr;
    void* global = globalInstance ? globalInstance() : nullptr;
    qDebug() << "[NeteasePlayer] instances: mediaManager=" << mediaManager
             << "mpm=" << mpm << "global=" << global;

    // ========== Step 2: wipeData（PenMods 必备） ==========
    if (wipeData && mpm) {
        qDebug() << "[NeteasePlayer] step2: wipeData...";
        wipeData(mpm);
        qDebug() << "[NeteasePlayer] step2: wipeData done";
    }

    // ========== Step 3: setAudioPlayingColomnId("myimport")（PenMods 必备） ==========
    if (setColumn && global) {
        qDebug() << "[NeteasePlayer] step3: setAudioPlayingColomnId(myimport)...";
        bool ret = setColumn(global, QString("myimport"));
        qDebug() << "[NeteasePlayer] step3: setColumn returned" << ret;
    }

    // ========== Step 4: 创建 YColumnMediaEntity（完全对齐 PenMods 字段） ==========
    qDebug() << "[NeteasePlayer] step4: create entity, sizeof=" << sizeof(YColumnMediaEntity);
    void* memory = new char[sizeof(YColumnMediaEntity)];
    memset(memory, 0, sizeof(YColumnMediaEntity));
    entityCtor(memory, nullptr);
    YColumnMediaEntity* entity = reinterpret_cast<YColumnMediaEntity*>(memory);

    static int mediaId = 0;
    mediaId--;
    entity->mId              = mediaId;
    entity->mMediaId         = QString::number(mediaId);
    entity->mOwnerId         = "fake_column_hsxjsbw";  // PenMods 的 PLAYER_FAKE_COLUMN_ID
    entity->mColumnId        = "fake_column_hsxjsbw";
    entity->mIsDir           = false;
    entity->mDownloadState   = 1;  // DownloadState::SUCCEED (PenMods 枚举值)
    entity->mTitle           = fi.fileName();
    entity->mLocalFile       = filePath;  // mp3 直接用原路径，不需要软链接
    entity->mDuration        = 0;
    entity->mProgress        = 0;
    entity->mSrcAudioVisible = true;
    qDebug() << "[NeteasePlayer] step4: entity ready, title=" << entity->mTitle
             << "file=" << entity->mLocalFile;

    // ========== Step 5: playAudio（核心播放） ==========
    qDebug() << "[NeteasePlayer] step5: playAudio...";
    void* result = playAudio(mediaManager, entity, true);
    qDebug() << "[NeteasePlayer] step5: playAudio returned" << result;

    // ========== Step 6: showAudioPlayer（弹出系统播放器界面） ==========
    if (showPlayer && global) {
        qDebug() << "[NeteasePlayer] step6: showAudioPlayer...";
        showPlayer(global);
        qDebug() << "[NeteasePlayer] step6: showAudioPlayer done";
    }

    // ========== Step 7: 检查播放状态，未播放则调用 onClickedPlay ==========
    if (mpm && playState && onClickedPlay) {
        int state = playState(mpm);
        qDebug() << "[NeteasePlayer] step7: playState=" << state << "(PLAYING=2)";
        if (state != 2) {  // PlayState::PLAYING
            qDebug() << "[NeteasePlayer] step7: not playing, calling onClickedPlay...";
            onClickedPlay(mpm);
            qDebug() << "[NeteasePlayer] step7: onClickedPlay done";
        }
    }

    // ========== 清理 ==========
    delete[] memory;
    m_source = filePath;
    emit sourceChanged(filePath);
    setPlaying(true);
    qDebug() << "[NeteasePlayer] DONE: system player playback started";
}
