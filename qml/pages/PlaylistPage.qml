import QtQuick 2.12
import "../components"

Rectangle {
    id: playlistPage
    objectName: "playlist"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal playSong(var song)
    signal playAll(var songs)
    signal loaded(var item)

    property string playlistId: ""
    property string playlistName: "歌单"
    property string coverImgUrl: ""
    property int playCount: 0
    property var songs: []
    property bool loading: false

    // 批量下载状态
    property bool batchDownloading: false
    property int batchTotal: 0
    property int batchDone: 0
    property int batchFailed: 0
    property string batchCurrentName: ""

    Component.onCompleted: playlistPage.loaded(playlistPage)

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
                    onClicked: playlistPage.backClicked()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: playlistPage.playlistName
                color: Theme.textPrimary
                font.pixelSize: Theme.fontNormal
                font.bold: true
                font.family: Theme.fontFamily
                elide: Text.ElideRight
                width: parent.width - 40
            }
        }
    }

    // ── 歌单信息区（封面+名称+数量）──
    Rectangle {
        id: infoBar
        width: parent.width
        height: 52
        color: Theme.bgSecondary
        anchors.top: topBar.bottom

        Rectangle {
            width: parent.width
            height: 1
            anchors.bottom: parent.bottom
            color: Theme.borderLight
        }

        Row {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8

            // 封面图
            Rectangle {
                width: 40
                height: 40
                radius: Theme.radiusMedium
                clip: true
                color: Theme.bgTertiary
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: playlistPage.coverImgUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 80
                    sourceSize.height: 80
                }

                // 无封面时显示音乐图标
                Text {
                    anchors.centerIn: parent
                    text: "♪"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontLarge
                    visible: !coverImage.status || coverImage.status === Image.Error
                }
            }

            // 歌单信息
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                width: parent.width - 56

                Text {
                    text: playlistPage.playlistName
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.bold: true
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                    maximumLineCount: 1
                }

                Text {
                    text: (playlistPage.playCount > 0 ? "播放量: " + (playlistPage.playCount >= 10000 ? (playlistPage.playCount / 10000).toFixed(1) + "万" : playlistPage.playCount) + "  ·  " : "") + playlistPage.songs.length + " 首歌曲"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                }
            }
        }
    }

    // ── 操作栏（播放全部 + 下载全部）──
    Rectangle {
        id: actionBar
        width: parent.width
        height: 28
        color: Theme.bgSecondary
        anchors.top: infoBar.bottom

        Rectangle {
            width: parent.width
            height: 1
            anchors.bottom: parent.bottom
            color: Theme.borderLight
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            // 播放全部
            Rectangle {
                width: (parent.width - 8) / 2
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: playAllMouse.pressed ? Theme.primaryDark : Theme.primary
                radius: Theme.radiusRound

                scale: playAllMouse.pressed ? 0.93 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                Text {
                    anchors.centerIn: parent
                    text: "▶ 播放全部"
                    color: Theme.textOnPrimary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    font.bold: true
                }

                MouseArea {
                    id: playAllMouse
                    anchors.fill: parent
                    onClicked: if (playlistPage.songs.length > 0) playlistPage.playAll(playlistPage.songs)
                }
            }

            // 下载全部
            Rectangle {
                width: (parent.width - 8) / 2
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: downloadAllMouse.pressed ? Theme.bgCardHover : Theme.bgCard
                border.color: Theme.primary
                border.width: 1
                radius: Theme.radiusRound

                scale: downloadAllMouse.pressed ? 0.93 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                Text {
                    anchors.centerIn: parent
                    text: playlistPage.batchDownloading ? "下载中..." : "↓ 下载全部"
                    color: Theme.primary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    font.bold: true
                }

                MouseArea {
                    id: downloadAllMouse
                    anchors.fill: parent
                    onClicked: if (!playlistPage.batchDownloading && playlistPage.songs.length > 0) playlistPage.startBatchDownload()
                }
            }
        }
    }

    // ── 批量下载进度条 ──
    Rectangle {
        id: batchProgressBar
        width: parent.width
        height: 22
        color: Theme.bgCard
        anchors.top: actionBar.bottom
        visible: playlistPage.batchDownloading

        Rectangle {
            id: batchProgressFill
            height: parent.height
            color: Theme.withAlpha(Theme.primary, 0.3)
            width: playlistPage.batchTotal > 0 ? (playlistPage.batchDone / playlistPage.batchTotal) * parent.width : 0
        }

        Text {
            anchors.centerIn: parent
            text: "下载中 " + playlistPage.batchDone + "/" + playlistPage.batchTotal + "  " + playlistPage.batchCurrentName
            color: Theme.textPrimary
            font.pixelSize: Theme.fontTiny
            font.family: Theme.fontFamily
        }
    }

    // ── 加载状态 ──
    Text {
        anchors.centerIn: parent
        text: playlistPage.loading ? "加载中..." : "暂无歌曲"
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSmall
        font.family: Theme.fontFamily
        visible: playlistPage.songs.length === 0
    }

    // ── 歌曲列表 ──
    ListView {
        id: songList
        anchors.top: batchProgressBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        visible: playlistPage.songs.length > 0
        model: playlistPage.songs

        delegate: Rectangle {
            width: parent.width
            height: 28
            color: index % 2 === 0 ? Theme.bgPrimary : Theme.bgCard

            scale: songMouse.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: 60 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                // 序号
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: index + 1
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    width: 16
                    horizontalAlignment: Text.AlignHCenter
                }

                // 歌曲信息
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 50
                    spacing: 0

                    Text {
                        text: modelData.name
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: modelData.artist
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                // 播放按钮
                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    color: playBtnMouse.pressed ? Theme.primaryDark : Theme.primary
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        color: "white"
                        font.pixelSize: 8
                    }

                    MouseArea {
                        id: playBtnMouse
                        anchors.fill: parent
                        onClicked: playlistPage.playSong(modelData)
                    }
                }
            }

            MouseArea {
                id: songMouse
                anchors.fill: parent
                onClicked: playlistPage.playSong(modelData)
            }
        }
    }

    // ── 加载歌单 ──
    function load(id) {
        if (!id) return
        playlistPage.playlistId = id
        playlistPage.loading = true
        playlistPage.songs = []
        playlistPage.coverImgUrl = ""
        playlistPage.playCount = 0

        if (id === "daily") {
            ApiClient.dailyRecommend(function(d) {
                playlistPage.loading = false
                playlistPage.playlistName = "每日推荐"
                if (d.code === 200 && d.data && d.data.dailySongs) {
                    parseSongs(d.data.dailySongs)
                }
            }, function(e) { playlistPage.loading = false })
        } else {
            ApiClient.playlistDetail(id, function(d) {
                playlistPage.loading = false
                if (d.code === 200 && d.playlist) {
                    playlistPage.playlistName = d.playlist.name
                    playlistPage.coverImgUrl = d.playlist.coverImgUrl || d.playlist.picUrl || ""
                    playlistPage.playCount = d.playlist.playCount || 0
                    parseSongs(d.playlist.tracks || [])
                }
            }, function(e) { playlistPage.loading = false })
        }
    }

    function parseSongs(tracks) {
        var list = []
        for (var i = 0; i < Math.min(tracks.length, 50); i++) {
            var s = tracks[i]
            var artists = []
            if (s.ar) for (var j = 0; j < s.ar.length; j++) artists.push(s.ar[j].name)
            list.push({
                id: s.id,
                name: s.name,
                artist: artists.join(" / "),
                album: s.al ? s.al.name : "",
                duration: s.dt || 0,
                cover: s.al ? (s.al.picUrl || "") : ""
            })
        }
        playlistPage.songs = list
    }

    // ── 批量下载 ──
    function startBatchDownload() {
        if (playlistPage.songs.length === 0) return
        var taskList = []
        for (var i = 0; i < playlistPage.songs.length; i++) {
            var s = playlistPage.songs[i]
            taskList.push({ id: s.id, name: s.name, artist: s.artist })
        }
        playlistPage.batchTotal = taskList.length
        playlistPage.batchDone = 0
        playlistPage.batchFailed = 0
        playlistPage.batchCurrentName = taskList[0].name
        playlistPage.batchDownloading = true

        ApiClient.batchStart(taskList, function(d) {
            if (d.code === 200) {
                console.log("[batch] 开始批量下载，共", d.total, "首")
                batchStatusTimer.start()
            }
        }, function(e) {
            console.log("[batch] 启动失败:", e)
            playlistPage.batchDownloading = false
        })
    }

    function checkBatchStatus() {
        ApiClient.batchStatus(function(d) {
            if (d.code === 200 && d.status) {
                var s = d.status
                playlistPage.batchDone = s.done
                playlistPage.batchFailed = s.failed
                playlistPage.batchCurrentName = s.currentName || ""
                if (s.finished || s.cancelled || !s.running) {
                    playlistPage.batchDownloading = false
                    batchStatusTimer.stop()
                    console.log("[batch] 完成，成功:", s.done, "失败:", s.failed, "跳过:", s.skipped)
                }
            }
        }, function(e) {
            console.log("[batch] 查询状态失败:", e)
        })
    }

    Timer {
        id: batchStatusTimer
        interval: 1000
        repeat: true
        onTriggered: playlistPage.checkBatchStatus()
    }
}
