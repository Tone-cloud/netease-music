import QtQuick 2.12
import NeteasePlayer 1.0
import "../components"

/**
 * 播放器页面
 * 功能：歌曲播放、歌词显示、听歌记录提交、下载
 */
Rectangle {
    id: playerPage
    objectName: "player"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    // ── 信号 ──
    signal backClicked()
    signal prevSong()
    signal nextSong()
    signal downloadRequested(var song)

    // ── 属性 ──
    property NeteasePlayer player: null
    property var currentSong: null
    property string lyricText: ""
    property var lyricLines: []
    property int lyricIndex: -1
    property bool loadingUrl: false
    property string playUrl: ""
    property bool caching: false

    // 听歌记录相关
    property int playStartTime: 0      // 实际开始播放的时间戳
    property var lastSongId: null      // 上一首歌的 ID
    property bool playStarted: false   // 是否已实际开始播放

    // ── 播放器信号监听 ──
    Connections {
        target: player
        function onPositionChanged(ms) { updateLyric(ms) }
        function onFinished() {
            // 播放完成：提交记录 + 自动下一首
            flushScrobble()
            playerPage.nextSong()
        }
        function onErrorOccurred(msg) {
            statusText.text = "错误: " + msg
            playerPage.caching = false
        }
    }

    // ── 缓存检查定时器：轮询播放是否真正开始 ──
    Timer {
        id: cacheCheckTimer
        interval: 500
        repeat: true
        onTriggered: {
            if (player && player.playing) {
                playerPage.caching = false
                statusText.text = "已通过系统播放器播放"
                cacheCheckTimer.stop()
                // 记录实际开始播放时间（用于听歌记录）
                if (!playerPage.playStarted) {
                    playerPage.playStartTime = Math.floor(Date.now() / 1000)
                    playerPage.playStarted = true
                    console.log("[scrobble] 实际开始播放:", playerPage.currentSong.name)
                }
            }
        }
    }

    // ── 歌曲切换处理 ──
    onCurrentSongChanged: {
        console.log("[PlayerPage] currentSong changed:",
                    currentSong ? currentSong.name : "null",
                    "player:", player ? "valid" : "null")
        // 切换歌曲时，先提交上一首歌的记录
        flushScrobble()
        if (currentSong && currentSong.id) {
            lastSongId = currentSong.id
            playStarted = false
            loadAndPlay()
        }
    }

    // ======================================================================
    // 听歌记录相关函数
    // ======================================================================

    /**
     * 提交上一首歌的听歌记录（播放超过30秒才算有效）
     * 在切换歌曲、播放完成、退出页面时调用
     */
    function flushScrobble() {
        if (!lastSongId || !playStarted) return
        var now = Math.floor(Date.now() / 1000)
        var playTime = now - playStartTime
        if (playTime < 30) {
            console.log("[scrobble] 播放时长不足30秒，跳过:", playTime, "秒")
            lastSongId = null
            playStarted = false
            return
        }
        console.log("[scrobble] 提交听歌记录: id=", lastSongId, "time=", playTime, "秒")
        ApiClient.scrobble(lastSongId, 0, playTime, function(d) {
            console.log("[scrobble] 提交成功: code=", d.code)
        }, function(e) {
            console.log("[scrobble] 提交失败:", e)
        })
        lastSongId = null
        playStarted = false
    }

    // ======================================================================
    // 播放相关函数
    // ======================================================================

    /**
     * 获取播放地址并开始播放
     */
    function loadAndPlay() {
        if (!currentSong || !currentSong.id) return
        console.log("[PlayerPage] loadAndPlay start, song:", currentSong.name)

        playerPage.loadingUrl = true
        playerPage.caching = false
        statusText.text = "获取播放地址..."
        lyricText = ""
        lyricLines = []
        lyricIndex = -1

        ApiClient.songUrl(currentSong.id, function(d) {
            playerPage.loadingUrl = false
            if (d.code === 200 && d.data && d.data[0] && d.data[0].url) {
                playerPage.playUrl = d.data[0].url
                playerPage.caching = true
                statusText.text = "正在缓存..."
                console.log("[PlayerPage] got url, calling player.play")
                if (player) {
                    player.play(playerPage.playUrl)
                    cacheCheckTimer.start()
                } else {
                    playerPage.caching = false
                    console.log("[PlayerPage] ERROR: player is null!")
                }
                loadLyric(currentSong.id)
            } else {
                statusText.text = "无法播放（可能需要 VIP）"
                console.log("[PlayerPage] no url in response")
            }
        }, function(e) {
            playerPage.loadingUrl = false
            statusText.text = "获取地址失败: " + e
            console.log("[PlayerPage] songUrl error:", e)
        })
    }

    // ======================================================================
    // 歌词相关函数
    // ======================================================================

    /**
     * 加载歌词
     */
    function loadLyric(id) {
        ApiClient.lyric(id, function(d) {
            if (d.code === 200 && d.lrc && d.lrc.lyric) {
                parseLyric(d.lrc.lyric)
            }
        }, null)
    }

    /**
     * 解析 LRC 格式歌词
     */
    function parseLyric(lrc) {
        var lines = lrc.split("\n")
        var result = []
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/\[(\d+):(\d+)\.(\d+)\](.*)/)
            if (m) {
                var t = parseInt(m[1]) * 60000
                        + parseInt(m[2]) * 1000
                        + parseInt(m[3]) * 10
                result.push({ time: t, text: m[4].trim() })
            }
        }
        result.sort(function(a, b) { return a.time - b.time })
        playerPage.lyricLines = result
    }

    /**
     * 根据播放位置更新当前歌词
     */
    function updateLyric(pos) {
        if (lyricLines.length === 0) return
        for (var i = lyricLines.length - 1; i >= 0; i--) {
            if (pos >= lyricLines[i].time) {
                if (i !== lyricIndex) {
                    lyricIndex = i
                    lyricText = lyricLines[i].text
                }
                break
            }
        }
    }

    // ======================================================================
    // UI 部分
    // ======================================================================

    // ── 顶部栏 ──
    Rectangle {
        id: topBar
        width: parent.width
        height: Theme.titleBarHeight
        color: Theme.bgSecondary

        Rectangle {
            width: parent.width
            height: 1
            anchors.bottom: parent.bottom
            color: Theme.borderLight
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 4

            // 返回按钮
            Rectangle {
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                color: backMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                radius: Theme.radiusSmall

                Text {
                    anchors.centerIn: parent
                    text: "<"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontNormal
                    font.bold: true
                    font.family: Theme.fontFamily
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    onClicked: {
                        // 返回时提交听歌记录
                        playerPage.flushScrobble()
                        playerPage.backClicked()
                    }
                }
            }

            // 标题
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "正在播放"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontNormal
                font.bold: true
                font.family: Theme.fontFamily
            }

            Item { width: 1 }

            // 下载按钮
            Rectangle {
                width: 36
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: downloadMouse.pressed ? Theme.primaryDark : Theme.primary
                radius: Theme.radiusRound

                scale: downloadMouse.pressed ? 0.93 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                Text {
                    anchors.centerIn: parent
                    text: "下载"
                    color: Theme.textOnPrimary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    font.bold: true
                }

                MouseArea {
                    id: downloadMouse
                    anchors.fill: parent
                    onClicked: if (currentSong) playerPage.downloadRequested(currentSong)
                }
            }
        }
    }

    // ── 主内容区：歌曲信息 + 歌词 ──
    Column {
        id: contentColumn
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        // 歌曲信息卡片
        Rectangle {
            width: parent.width
            height: 56
            color: Theme.bgCard
            radius: Theme.radiusMedium
            border.color: Theme.borderLight
            border.width: 0.5

            Row {
                anchors.fill: parent
                anchors.margins: Theme.spacingSmall
                spacing: Theme.spacingMedium

                // 专辑封面
                Rectangle {
                    width: 40
                    height: 40
                    radius: Theme.radiusSmall
                    color: Theme.bgTertiary
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source: currentSong && currentSong.cover ? currentSong.cover : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: currentSong != null && currentSong.cover != ""
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "♪"
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontLarge
                        visible: currentSong == null || currentSong.cover == ""
                    }
                }

                // 歌曲信息（歌名/歌手/专辑）
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56
                    spacing: 2

                    Text {
                        text: currentSong ? currentSong.name : "—"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontNormal
                        font.bold: true
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: parent.width
                    }
                    Text {
                        text: currentSong ? currentSong.artist : "—"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: parent.width
                    }
                    Text {
                        text: currentSong ? (currentSong.album || "—") : "—"
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: parent.width
                    }
                }
            }
        }

        // 加载/缓存状态提示
        Row {
            visible: playerPage.caching || playerPage.loadingUrl
            width: parent.width
            spacing: 6

            Rectangle {
                width: 12
                height: 12
                radius: 6
                color: Theme.primary
                RotationAnimation on rotation {
                    running: true
                    duration: 1000
                    from: 0
                    to: 360
                    loops: Animation.Infinite
                }
            }
            Text {
                text: playerPage.loadingUrl ? "获取播放地址..." : "正在缓存下载..."
                color: Theme.primary
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // 歌词显示区域
        Rectangle {
            width: parent.width
            height: parent.height - 80
            color: Theme.bgCard
            radius: Theme.radiusMedium
            border.color: Theme.borderLight
            border.width: 0.5
            visible: !playerPage.caching && !playerPage.loadingUrl

            Text {
                id: lyricDisplay
                anchors.centerIn: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                text: lyricText || statusText.text || "暂无歌词"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                width: parent.width - 20
            }
        }
    }

    // 隐藏的状态文本（用于歌词后备显示）
    Text { id: statusText; visible: false; text: "就绪" }
}
