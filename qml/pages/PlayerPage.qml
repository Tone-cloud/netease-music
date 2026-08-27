import QtQuick 2.12
import NeteasePlayer 1.0
import "../components"

Rectangle {
    id: playerPage
    objectName: "player"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal prevSong()
    signal nextSong()
    signal downloadRequested(var song)

    property NeteasePlayer player: null
    property var currentSong: null
    property string lyricText: ""
    property var lyricLines: []
    property int lyricIndex: -1
    property bool loadingUrl: false
    property string playUrl: ""
    property bool caching: false

    // 监听播放器信号
    Connections {
        target: player
        function onPositionChanged(ms) { updateLyric(ms) }
        function onFinished() { playerPage.nextSong() }
        function onErrorOccurred(msg) { statusText.text = "错误: " + msg; playerPage.caching = false }
    }

    // 缓存检查：轮询播放是否开始
    Timer {
        id: cacheCheckTimer
        interval: 500
        repeat: true
        onTriggered: {
            if (player && player.playing) {
                playerPage.caching = false
                statusText.text = "已通过系统播放器播放"
                cacheCheckTimer.stop()
            }
        }
    }

    // 当 currentSong 变化时，获取播放地址并播放
    onCurrentSongChanged: {
        console.log("[PlayerPage] currentSong changed:", currentSong ? currentSong.name : "null", "player:", player ? "valid" : "null")
        if (currentSong && currentSong.id) {
            loadAndPlay()
        }
    }

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

    function loadLyric(id) {
        ApiClient.lyric(id, function(d) {
            if (d.code === 200 && d.lrc && d.lrc.lyric) {
                parseLyric(d.lrc.lyric)
            }
        }, null)
    }

    function parseLyric(lrc) {
        var lines = lrc.split("\n")
        var result = []
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/\[(\d+):(\d+)\.(\d+)\](.*)/)
            if (m) {
                var t = parseInt(m[1]) * 60000 + parseInt(m[2]) * 1000 + parseInt(m[3]) * 10
                result.push({ time: t, text: m[4].trim() })
            }
        }
        result.sort(function(a, b) { return a.time - b.time })
        playerPage.lyricLines = result
    }

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

    // 顶部栏
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
                    onClicked: playerPage.backClicked()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "正在播放"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontNormal
                font.bold: true
                font.family: Theme.fontFamily
            }

            Item { width: 1 }

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

    // 主内容区：歌曲信息 + 歌词
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

                // 专辑封面占位
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
                        visible: currentSong && currentSong.cover
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "♪"
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontLarge
                        visible: !(currentSong && currentSong.cover)
                    }
                }

                // 歌曲信息
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
                        text: currentSong ? currentSong.album : "—"
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

        // 状态/缓存提示
        Row {
            visible: playerPage.caching || playerPage.loadingUrl
            width: parent.width
            spacing: 6

            Rectangle {
                width: 12
                height: 12
                radius: 6
                color: Theme.primary
                RotationAnimation on rotation { running: true; duration: 1000; from: 0; to: 360; loops: Animation.Infinite }
            }
            Text {
                text: playerPage.loadingUrl ? "获取播放地址..." : "正在缓存下载..."
                color: Theme.primary
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // 歌词区域
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

    // 状态文本（隐藏，用于歌词后备）
    Text { id: statusText; visible: false; text: "就绪" }
}
