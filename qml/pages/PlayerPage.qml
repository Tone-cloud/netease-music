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
    signal autoNext()               // 播放结束后请求自动续播下一首

    // ── 属性 ──
    property NeteasePlayer player: null
    property var currentSong: null
    property var playlist: []       // 播放列表
    property int currentIndex: 0    // 当前播放索引
    property bool loadingUrl: false
    property string playUrl: ""
    property bool caching: false
    property string playState: "idle"    // idle/loading/playing/error
    property bool autoPlayNext: false    // 本次切歌由播放结束自动触发，切完直接播放

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
        playerPage.autoPlayNext = false
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
            playerPage.caching = false
            // 播放结束后按歌单顺序自动续播下一首
            playerPage.autoPlayNext = true
            playerPage.autoNext()
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
            // 切歌时唱片旋转归零
            if (discPlate) discPlate.rotation = 0
            if (playerPage.autoPlayNext === true) {
                // 自动续播/按下一首：直接开始播放，不需要用户再点播放
                playerPage.autoPlayNext = false
                if (currentSong.downloaded === true) {
                    setPlayState("loading", "正在播放下一首...")
                    loadAndPlay()
                } else {
                    setPlayState("idle", "下一首还未下载，请先下载")
                }
            } else if (currentSong.downloaded === true) {
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
                width: 26
                height: 26
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

            // 上一首
            Rectangle {
                width: 28
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                color: prevMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                radius: Theme.radiusSmall
                Text {
                    anchors.centerIn: parent
                    text: "|<"
                    color: playerPage.playlist.length > 1 ? Theme.textPrimary : Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    enabled: playerPage.playlist.length > 1
                    onClicked: playerPage.prevSong()
                }
            }

            // 下一首
            Rectangle {
                width: 28
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                color: nextMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                radius: Theme.radiusSmall
                Text {
                    anchors.centerIn: parent
                    text: ">|"
                    color: playerPage.playlist.length > 1 ? Theme.textPrimary : Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    enabled: playerPage.playlist.length > 1
                    onClicked: playerPage.nextSong()
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

    // ── 主内容区 ──
    Column {
        id: contentColumn
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        // 歌曲信息卡片（旋转唱片 + 歌名/歌手/专辑）
        Rectangle {
            width: parent.width
            height: 74
            color: Theme.bgCard
            radius: Theme.radiusMedium
            border.color: Theme.borderLight
            border.width: 0.5

            Row {
                anchors.fill: parent
                anchors.margins: Theme.spacingSmall
                spacing: Theme.spacingMedium

                // ── 唱片区：旋转黑胶 + 居中方形封面 + 中心轴 ──
                Item {
                    width: 66
                    height: 66
                    anchors.verticalCenter: parent.verticalCenter

                    // 旋转黑胶（Canvas 一次绘制唱片纹路，整体旋转）
                    Canvas {
                        id: discPlate
                        anchors.fill: parent
                        antialiasing: true
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var c = width / 2
                            ctx.beginPath()
                            ctx.arc(c, c, c - 1, 0, Math.PI * 2)
                            ctx.fillStyle = "#151515"
                            ctx.fill()
                            ctx.lineWidth = 1
                            for (var r = 7; r < c - 1; r += 4) {
                                ctx.beginPath()
                                ctx.arc(c, c, r, 0, Math.PI * 2)
                                ctx.strokeStyle = "#2E2E2E"
                                ctx.stroke()
                            }
                            ctx.beginPath()
                            ctx.arc(c, c, 3, 0, Math.PI * 2)
                            ctx.fillStyle = "#0D0D0D"
                            ctx.fill()
                        }
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        RotationAnimation on rotation {
                            running: playerPage.playState === "playing"
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 9000
                            easing.type: Easing.Linear
                        }
                    }

                    // 播放中发光环
                    Rectangle {
                        anchors.centerIn: parent
                        width: 60
                        height: 60
                        radius: 30
                        color: "transparent"
                        border.color: Theme.primaryGlow
                        border.width: 2
                        visible: playerPage.playState === "playing"
                    }

                    // 居中封面
                    Rectangle {
                        width: 46
                        height: 46
                        radius: 10
                        clip: true
                        color: Theme.bgTertiary
                        anchors.centerIn: parent
                        z: 1

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

                    // 中心轴
                    Rectangle {
                        width: 7
                        height: 7
                        radius: 4
                        color: "#F0F0F0"
                        border.color: Theme.primary
                        border.width: 1
                        anchors.centerIn: parent
                        z: 2
                    }
                }

                // 歌曲信息（歌名/歌手/专辑）
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 82
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

        // ── 状态提示行（始终可见）──
        Row {
            width: parent.width
            spacing: 6

            // 加载中旋转点
            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: Theme.primary
                visible: playerPage.caching || playerPage.loadingUrl
                RotationAnimation on rotation {
                    running: visible
                    duration: 1000
                    from: 0
                    to: 360
                    loops: Animation.Infinite
                }
            }

            Text {
                id: statusText
                text: "就绪"
                color: playerPage.playState === "error" ? Theme.error
                      : (playerPage.playState === "loading" ? Theme.primary : Theme.textSecondary)
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                width: parent.width - 16
            }
        }

        // ── 操作按钮行：播放 + 下载 ──
        Row {
            width: parent.width
            spacing: Theme.spacingMedium

            // 播放按钮
            Rectangle {
                width: (parent.width - Theme.spacingMedium) / 2
                height: 30
                radius: Theme.radiusRound
                color: playMouse.pressed ? Theme.primaryDark : Theme.primary
                enabled: currentSong && currentSong.downloaded === true
                opacity: enabled ? 1 : 0.45

                scale: playMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: playerPage.playState === "playing" ? "重新播放" : "播放"
                    color: Theme.textOnPrimary
                    font.pixelSize: Theme.fontBody
                    font.bold: true
                    font.family: Theme.fontFamily
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
                width: (parent.width - Theme.spacingMedium) / 2
                height: 30
                radius: Theme.radiusRound
                color: downloadMouse.pressed ? Theme.bgCardHover : Theme.bgCard
                border.color: Theme.primary
                border.width: 1

                scale: downloadMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: (currentSong && currentSong.downloaded === true) ? "已下载 ✓" : "下载"
                    color: (currentSong && currentSong.downloaded === true) ? Theme.success : Theme.primary
                    font.pixelSize: Theme.fontBody
                    font.bold: true
                    font.family: Theme.fontFamily
                }

                MouseArea {
                    id: downloadMouse
                    anchors.fill: parent
                    onClicked: if (currentSong) playerPage.showDownloadChoice()
                }
            }
        }
    }
}
