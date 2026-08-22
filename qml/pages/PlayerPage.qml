import QtQuick 2.12
import "../components"

Rectangle {
    id: root
    objectName: "player"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal prevSong()
    signal nextSong()
    signal downloadRequested(var song)

    property var player: null          // 全局 NeteasePlayer 实例
    property var currentSong: null
    property string lyricText: ""
    property var lyricLines: []
    property int lyricIndex: -1
    property bool loadingUrl: false
    property string playUrl: ""

    // 监听播放器信号
    Connections {
        target: root.player
        function onPositionChanged(ms) { updateLyric(ms) }
        function onFinished() { root.nextSong() }
        function onErrorOccurred(msg) { statusText.text = "错误: " + msg }
    }

    // 当 currentSong 变化时，获取播放地址并播放
    onCurrentSongChanged: {
        if (currentSong && currentSong.id) {
            loadAndPlay()
        }
    }

    function loadAndPlay() {
        if (!currentSong || !currentSong.id) return
        root.loadingUrl = true
        statusText.text = "获取播放地址..."
        lyricText = ""
        lyricLines = []
        lyricIndex = -1
        // 先获取播放地址
        ApiClient.songUrl(currentSong.id, function(d) {
            root.loadingUrl = false
            if (d.code === 200 && d.data && d.data[0] && d.data[0].url) {
                root.playUrl = d.data[0].url
                statusText.text = "正在播放: " + currentSong.name
                // 用 FFmpeg 直接播放 HTTP URL
                root.player.play(root.playUrl)
                loadLyric(currentSong.id)
            } else {
                statusText.text = "无法播放（可能需要 VIP）"
            }
        }, function(e) {
            root.loadingUrl = false
            statusText.text = "获取地址失败: " + e
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
        root.lyricLines = result
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

    function formatTime(ms) {
        var s = Math.floor(ms / 1000)
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    // 顶部栏
    Rectangle {
        id: topBar
        width: parent.width; height: 26
        color: Theme.bgSecondary
        Row {
            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 4
            Rectangle {
                width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "<"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.backClicked() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: currentSong ? currentSong.name : "未播放"
                color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true
                font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width - 100
            }
            Item { width: 1 }
            Rectangle {
                width: 36; height: 20; anchors.verticalCenter: parent.verticalCenter
                color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "下载"; color: Theme.success; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: if (currentSong) root.downloadRequested(currentSong) }
            }
        }
    }

    // 主内容区
    Row {
        id: contentRow
        anchors.top: topBar.bottom; anchors.bottom: progressBar.top
        anchors.left: parent.left; anchors.right: parent.right
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingL

        // 专辑封面（旋转动画）
        Rectangle {
            width: 70; height: 70; anchors.verticalCenter: parent.verticalCenter
            color: Theme.bgCard; radius: 35
            border.color: Theme.accent; border.width: 1
            Text { anchors.centerIn: parent; text: "♫"; color: Theme.accentSoft; font.pixelSize: 28 }
            RotationAnimation on rotation {
                running: root.player && root.player.playing
                duration: 6000; from: 0; to: 360; loops: Animation.Infinite
            }
        }

        // 歌曲信息 + 歌词
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 90; spacing: Theme.spacingXS
            Text { text: currentSong ? currentSong.name : "—"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily; elide: Text.ElideRight; maximumLineCount: 1; width: parent.width }
            Text { text: currentSong ? currentSong.artist : "—"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily; elide: Text.ElideRight; maximumLineCount: 1; width: parent.width }
            Text { text: currentSong ? currentSong.album : "—"; color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily; elide: Text.ElideRight; maximumLineCount: 1; width: parent.width }
            Rectangle { width: parent.width; height: 1; color: Theme.divider }
            Text {
                id: lyricDisplay
                text: lyricText || statusText.text
                color: Theme.accentSoft; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
                elide: Text.ElideRight; maximumLineCount: 2; width: parent.width
            }
        }
    }

    // 状态文本（隐藏，用于歌词后备）
    Text { id: statusText; visible: false; text: "就绪" }

    // 进度条
    Rectangle {
        id: progressBar
        width: parent.width; height: 16
        anchors.bottom: controlBar.top
        color: Theme.bgSecondary
        Row {
            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 4
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: formatTime(root.player ? root.player.position : 0)
                color: Theme.textMuted; font.pixelSize: Theme.fontTiny
            }
            Rectangle {
                id: progressBg
                width: parent.width - 70; height: 3; anchors.verticalCenter: parent.verticalCenter
                color: Theme.bgCard; radius: 1
                Rectangle {
                    height: parent.height; radius: 1; color: Theme.accent
                    width: root.player && root.player.duration > 0
                        ? (root.player.position / root.player.duration) * parent.width : 0
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.player && root.player.duration > 0) {
                            var ratio = mouse.x / width
                            root.player.seek(Math.floor(ratio * root.player.duration))
                        }
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: formatTime(root.player ? root.player.duration : 0)
                color: Theme.textMuted; font.pixelSize: Theme.fontTiny
            }
        }
    }

    // 控制栏
    Rectangle {
        id: controlBar
        width: parent.width; height: 40
        anchors.bottom: parent.bottom
        color: Theme.bgSecondary
        Row {
            anchors.centerIn: parent; spacing: Theme.spacingXL
            // 上一首
            Rectangle {
                width: 32; height: 32; color: Theme.bgCard; radius: 16
                Text { anchors.centerIn: parent; text: "⏮"; color: Theme.textPrimary; font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; onClicked: root.prevSong() }
            }
            // 播放/暂停
            Rectangle {
                width: 38; height: 38
                color: root.player && root.player.playing ? Theme.accent : Theme.success
                radius: 19
                Text {
                    anchors.centerIn: parent
                    text: root.player && root.player.playing ? "⏸" : "▶"
                    color: "white"; font.pixelSize: 14
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.player) {
                            if (root.player.playing) root.player.pause()
                            else root.player.resume()
                        }
                    }
                }
            }
            // 停止
            Rectangle {
                width: 32; height: 32; color: Theme.bgCard; radius: 16
                Text { anchors.centerIn: parent; text: "⏹"; color: Theme.warning; font.pixelSize: 10 }
                MouseArea { anchors.fill: parent; onClicked: if (root.player) root.player.stop() }
            }
            // 下一首
            Rectangle {
                width: 32; height: 32; color: Theme.bgCard; radius: 16
                Text { anchors.centerIn: parent; text: "⏭"; color: Theme.textPrimary; font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; onClicked: root.nextSong() }
            }
        }
    }
}
