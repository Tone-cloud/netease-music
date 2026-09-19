#include "NeteasePlayer.h"
#include <QDebug>
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

#include <QHash>

// ========== ELF .symtab 符号解析器（带缓存） ==========
// dlsym 只能查 .dynsym（动态符号表），有道主程序的 C++ 符号在 .symtab（静态符号表）中，
// 没有被导出，所以需要自己解析 ELF 文件查找符号地址。
//
// 性能优化：符号表和字符串表只在第一次调用时读取并缓存，后续调用直接在缓存中搜索。
// 避免每次播放都重复读取 1MB 符号表 + 1.8MB 字符串表（约 200ms 开销）。

/// 缓存的 ELF 符号表数据
struct ElfSymbolCache {
    bool              inited = false;
    quint64           base = 0;
    QByteArray        strtab;        // 字符串表
    QVector<Elf64_Sym> symtab;      // 符号表
    QHash<QByteArray, void*> resolved;  // 已解析的符号地址缓存
};

static ElfSymbolCache &symbolCache() {
    static ElfSymbolCache cache;
    return cache;
}

/// 获取主程序路径
static QString getExePath() {
    char exePath[512];
    ssize_t len = readlink("/proc/self/exe", exePath, sizeof(exePath) - 1);
    if (len <= 0) return QString();
    exePath[len] = '\0';
    return QString::fromLocal8Bit(exePath);
}

/// 从 /proc/self/maps 获取主程序加载基地址
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

/// 初始化符号缓存（只执行一次）
static bool initSymbolCache() {
    ElfSymbolCache &cache = symbolCache();
    if (cache.inited) return true;

    cache.base = getMainBase();
    if (!cache.base) {
        qWarning() << "[resolveSymbol] failed to get base address";
        return false;
    }

    QString exePath = getExePath();
    if (exePath.isEmpty()) return false;
    QByteArray exeBa = exePath.toLocal8Bit();

    int fd = open(exeBa.constData(), O_RDONLY);
    if (fd < 0) {
        qWarning() << "[resolveSymbol] open failed:" << exePath;
        return false;
    }

    // 读取 ELF header
    Elf64_Ehdr ehdr;
    memset(&ehdr, 0, sizeof(ehdr));
    ssize_t r = read(fd, &ehdr, sizeof(ehdr));
    if (r != (ssize_t)sizeof(ehdr) || memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0) {
        qWarning() << "[resolveSymbol] invalid ELF file";
        close(fd);
        return false;
    }

    if (ehdr.e_shnum == 0 || ehdr.e_shoff == 0) {
        qWarning() << "[resolveSymbol] no section headers";
        close(fd);
        return false;
    }

    // 读取 section header table
    size_t shdrSize = sizeof(Elf64_Shdr) * ehdr.e_shnum;
    QVector<Elf64_Shdr> shdrs(ehdr.e_shnum);
    lseek(fd, ehdr.e_shoff, SEEK_SET);
    r = read(fd, shdrs.data(), shdrSize);
    if (r != (ssize_t)shdrSize) {
        qWarning() << "[resolveSymbol] read shdrs failed";
        close(fd);
        return false;
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
        close(fd);
        return false;
    }

    qDebug() << "[resolveSymbol] caching symtab:" << symtabSec->sh_size
             << "bytes, strtab:" << strtabSec->sh_size << "bytes";

    // 读取字符串表到缓存
    cache.strtab.resize(strtabSec->sh_size);
    lseek(fd, strtabSec->sh_offset, SEEK_SET);
    read(fd, cache.strtab.data(), strtabSec->sh_size);

    // 读取符号表到缓存
    int symCount = (int)(symtabSec->sh_size / sizeof(Elf64_Sym));
    cache.symtab.resize(symCount);
    lseek(fd, symtabSec->sh_offset, SEEK_SET);
    read(fd, cache.symtab.data(), symtabSec->sh_size);

    close(fd);
    cache.inited = true;
    qDebug() << "[resolveSymbol] symbol cache initialized, total symbols:" << symCount;
    return true;
}

/// 解析主程序 ELF 的 .symtab 段，按符号名查找地址（带缓存）
static void *resolveSymbol(const char *name) {
    if (!name) return nullptr;

    ElfSymbolCache &cache = symbolCache();

    // 先查已解析缓存
    QByteArray key(name);
    auto it = cache.resolved.constFind(key);
    if (it != cache.resolved.constEnd()) {
        return it.value();
    }

    // 初始化符号表（只执行一次）
    if (!cache.inited && !initSymbolCache()) {
        return nullptr;
    }

    // 在缓存的符号表中搜索
    void *result = nullptr;
    const char *strs = cache.strtab.constData();
    int symCount = cache.symtab.size();
    for (int i = 0; i < symCount; i++) {
        const Elf64_Sym &sym = cache.symtab[i];
        if (sym.st_name >= (quint64)cache.strtab.size()) continue;
        const char *symName = strs + sym.st_name;
        if (!symName) continue;
        if (strcmp(symName, name) == 0 && sym.st_value != 0) {
            result = reinterpret_cast<void*>(sym.st_value);
            qDebug() << "[resolveSymbol] found" << name << "->" << result;
            break;
        }
    }

    if (!result) {
        qWarning() << "[resolveSymbol] symbol not found:" << name;
    }

    // 存入已解析缓存（包括 nullptr，避免重复查找不存在的符号）
    cache.resolved.insert(key, result);
    return result;
}

static bool hasSystemPlayerSymbols() {
    const char *required[] = {
        "_ZN10YSingletonI13YMediaManagerE8instanceEv",
        "_ZN18YColumnMediaEntityC2EP7QObject",
        "_ZN13YMediaManager9playAudioERK18YColumnMediaEntityb",
        "_ZN7YGlobal23setAudioPlayingColomnIdERK7QString",
        "_ZN7YGlobal15showAudioPlayerEv",
        "_ZN19YMediaPlayerManager13onClickedPlayEv",
        "_ZNK19YMediaPlayerManager9playStateEv"
    };

    for (const char *name : required) {
        if (!resolveSymbol(name)) {
            qWarning() << "[systemPlayer] missing required symbol:" << name;
            return false;
        }
    }
    return true;
}

NeteasePlayer::NeteasePlayer(QObject *parent)
    : QObject(parent) {
    m_networkManager = new QNetworkAccessManager(this);
}

NeteasePlayer::~NeteasePlayer() {
    stop();
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
        QString cacheUrl = QString("http://127.0.0.1:8002/cache?url=%1").arg(QString::fromUtf8(encoded));
        qDebug() << "[NeteasePlayer] requesting cache:" << cacheUrl;

        QUrl reqUrl(cacheUrl);
        QNetworkRequest request(reqUrl);
        m_cacheReply = m_networkManager->get(request);
        connect(m_cacheReply, &QNetworkReply::finished, this, &NeteasePlayer::onCacheReply);
        return;
    }

    // 设备上只有系统播放器，不再走内置 QAudioOutput 解码器分支
    playWithSystemPlayer(source);
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

    // 只使用系统播放器：缓存完本地文件后继续通过原生播放器播放
    playWithSystemPlayer(localPath);
}

void NeteasePlayer::stop() {
    if (m_systemPlayerTimer) m_systemPlayerTimer->stop();
    m_usingSystemPlayer = false;
    m_playing = false;
}

void NeteasePlayer::setPlaying(bool p) {
    if (m_playing != p) {
        m_playing = p;
    }
}

void NeteasePlayer::startServer(const QString &path) {
    if (path.isEmpty()) return;
    // 先杀掉旧进程
    QProcess::execute("pkill", QStringList() << "-f" << path);
    // 确保有执行权限，然后启动（用 sh -c 确保 chmod 成功后再启动）
    QString cmd = QString("chmod +x %1 && %1").arg(path);
    bool ok = QProcess::startDetached("sh", QStringList() << "-c" << cmd);
    qInfo() << "Started server:" << path << "success:" << ok;
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

    if (!hasSystemPlayerSymbols()) {
        qCritical() << "[systemPlayer] required PenMods symbols missing; this device only supports the system player";
        emit errorOccurred("当前设备缺少系统播放器符号，无法播放");
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
    m_usingSystemPlayer = true;

    // 启动定时器轮询系统播放器状态，检测播放完成
    if (!m_systemPlayerTimer) {
        m_systemPlayerTimer = new QTimer(this);
        connect(m_systemPlayerTimer, &QTimer::timeout, this, &NeteasePlayer::checkSystemPlayerState);
    }
    m_systemPlayerTimer->start(2000);  // 每2秒检查一次
    qDebug() << "[NeteasePlayer] DONE: system player playback started, monitoring...";
}

// 轮询系统播放器状态，检测播放完成
void NeteasePlayer::checkSystemPlayerState() {
    if (!m_usingSystemPlayer || !m_playing) return;

    typedef int (*PlayStateFunc)(void*);
    PlayStateFunc playState = (PlayStateFunc)resolveSymbol("_ZNK19YMediaPlayerManager9playStateEv");
    typedef void* (*InstanceFunc)();
    InstanceFunc mpmInstance = (InstanceFunc)resolveSymbol("_ZN10YSingletonI19YMediaPlayerManagerE8instanceEv");

    if (!mpmInstance || !playState) return;

    void* mpm = mpmInstance();
    if (!mpm) return;

    int state = playState(mpm);
    // PlayState: 0=STOPPED, 1=PAUSED, 2=PLAYING
    if (state != 2 && m_playing) {
        qDebug() << "[NeteasePlayer] system player finished, state=" << state;
        m_systemPlayerTimer->stop();
        m_usingSystemPlayer = false;
        setPlaying(false);
        setPaused(false);
        emit finished();
    }
}
