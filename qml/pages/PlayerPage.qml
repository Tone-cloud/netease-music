import QtQuick 2.12
import NeteasePlayer 1.0
import "../components"

/**
 * 播放器页面
 * 功能：歌曲播放、听歌记录提交、下载
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
    signal downloadRequested(var song, bool withLyrics)

    // ── 属性 ──
    property NeteasePlayer player: null
    property var currentSong: null
    property var playlist: []       // 播放列表
    property int currentIndex: 0    // 当前播放索引
    property bool loadingUrl: false
    property string playUrl: ""
    property bool caching: false
    property string playState: "idle"    // idle/loading/playing/error

    // 听歌记录相关
    property int playStartTime: 0      // 实际开始播放的时间戳
    property var lastSongId: null      // 上一首歌的 ID
    property bool playStarted: false   // 是否已实际开始播放

    function setPlayState(state, message) {
        playerPage.playState = state
        if (message && message.length > 0) {
            statusText.text = message
        }
    }

    function showDownloadChoice() {
        if (!currentSong) return
        downloadDialog.visible = true
    }

    function startDownload(withLyrics) {
        downloadDialog.visible = false
        if (playerPage.downloadRequested) {
            playerPage.downloadRequested(currentSong, withLyrics)
        }
    }

    function resetPlaybackState() {
        playerPage.playStarted = false
        playerPage.playStartTime = 0
        playerPage.lastSongId = null
        playerPage.caching = false
        playerPage.loadingUrl = false
        playerPage.playUrl = ""
    }

    // ── 播放器信号监听 ──
    Connections {
        target: player
        function onSourceChanged(src) {
            if (src && src.length > 0 && playerPage.currentSong && playerPage.playState !== "playing") {
                playerPage.caching = false
                playerPage.setPlayState("playing", "已通过系统播放器播放")
                if (!playerPage.playStarted) {
                    playerPage.playStartTime = Math.floor(Date.now() / 1000)
                    playerPage.playStarted = true
                    console.log("[scrobble] 实际开始播放:", playerPage.currentSong.name)
                }
            }
        }
        function onFinished() {
            flushScrobble()
            playerPage.setPlayState("idle", "播放完成")
            playerPage.nextSong()
        }
        function onErrorOccurred(msg) {
            playerPage.setPlayState("error", "错误: " + msg)
            playerPage.caching = false
            playerPage.loadingUrl = false
        }
    }

    // ── 歌曲切换处理：默认不播放，等待用户下载完成后手动播放 ──
    onCurrentSongChanged: {
        console.log("[PlayerPage] currentSong changed:",
                    currentSong ? currentSong.name : "null",
                    "player:", player ? "valid" : "null")
        flushScrobble()
        if (currentSong && currentSong.id) {
            lastSongId = currentSong.id
            playStarted = false
            if (currentSong.downloaded === true) {
                setPlayState("idle", "已下载，可点击播放")
            } else {
                setPlayState("idle", "已选中，下载后再点击播放")
            }
        } else {
            resetPlaybackState()
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

    function loadAndPlay() {
        if (!currentSong || !currentSong.id) return
        if (currentSong.downloaded !== true || !currentSong.localPath) {
            playerPage.setPlayState("idle", "请先下载歌曲，再点击播放")
            return
        }

        console.log("[PlayerPage] playing local file:", currentSong.localPath)
        playerPage.loadingUrl = false
        playerPage.caching = false
        playerPage.setPlayState("loading", "正在打开本地歌曲...")

        if (!player) {
            playerPage.setPlayState("error", "播放器初始化失败")
            return
        }
        player.play(currentSong.localPath)
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

            // 标题 + 播放进度
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    text: "正在播放"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontNormal
                    font.bold: true
                    font.family: Theme.fontFamily
                }
                Text {
                    text: playerPage.playlist.length > 1 ? ("第 " + (playerPage.currentIndex + 1) + " / " + playerPage.playlist.length + " 首") : ""
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                }
            }

            Item { width: 1 }

            Rectangle {
                width: 24
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: prevMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                radius: Theme.radiusSmall
                Text {
                    anchors.centerIn: parent
                    text: "|<"
                    color: playerPage.playlist.length > 1 ? Theme.textPrimary : Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                }
                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    enabled: playerPage.playlist.length > 1
                    onClicked: playerPage.prevSong()
                }
            }

            Rectangle {
                width: 24
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: nextMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                radius: Theme.radiusSmall
                Text {
                    anchors.centerIn: parent
                    text: ">|"
                    color: playerPage.playlist.length > 1 ? Theme.textPrimary : Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                }
                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    enabled: playerPage.playlist.length > 1
                    onClicked: playerPage.nextSong()
                }
            }

            Rectangle {
                width: 36
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: playMouse.pressed ? Theme.primaryDark : Theme.primary
                radius: Theme.radiusRound
                enabled: currentSong && currentSong.downloaded === true
                opacity: enabled ? 1 : 0.5
                Text {
                    anchors.centerIn: parent
                    text: "播放"
                    color: Theme.textOnPrimary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    font.bold: true
                }
                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    enabled: currentSong && currentSong.downloaded === true
                    onClicked: if (currentSong && currentSong.downloaded === true) playerPage.loadAndPlay()
                }
            }

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
                    onClicked: if (currentSong) playerPage.showDownloadChoice()
                }
            }
        }
    }

    Rectangle {
        id: downloadDialog
        anchors.fill: parent
        color: "#80000000"
        visible: false
        z: 200

        Rectangle {
            width: 240
            height: 132
            radius: 10
            color: Theme.bgCard
            anchors.centerIn: parent
            border.color: Theme.borderLight
            border.width: 1
            z: 1

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Text {
                    text: "下载当前歌曲？"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                    font.bold: true
                }

                Text {
                    text: currentSong ? currentSong.name : ""
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                    maximumLineCount: 1
                }

                Text {
                    text: "将同时下载同名 .lrc 歌词文件"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                    maximumLineCount: 1
                }

                Row {
                    spacing: 8
                    Rectangle {
                        width: 108
                        height: 24
                        radius: 4
                        color: Theme.primary
                        Text {
                            anchors.centerIn: parent
                            text: "下载歌曲 + 歌词"
                            color: "white"
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: playerPage.startDownload(true)
                        }
                    }

                    Rectangle {
                        width: 52
                        height: 24
                        radius: 4
                        color: Theme.bgSecondary
                        Text {
                            anchors.centerIn: parent
                            text: "取消"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: downloadDialog.visible = false
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: downloadDialog.visible = false
        }
    }

    // ── 主内容区：歌曲信息 ──
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
            height: 72
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
                    width: 52
                    height: 52
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
                    width: parent.width - 68
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

    }

    // 隐藏的状态文本（用于显示播放状态提示）
    Text { id: statusText; visible: false; text: "就绪" }
}
