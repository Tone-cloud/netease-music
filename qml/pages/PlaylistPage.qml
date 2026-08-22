import QtQuick 2.12
import "../components"

Rectangle {
    id: root
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
    property var songs: []
    property bool loading: false

    Component.onCompleted: root.loaded(root)

    // 顶部栏
    Rectangle {
        id: topBar
        width: parent.width; height: 28
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
                text: root.playlistName; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true
                font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width - 80
            }
            Item { width: 1 }
            Rectangle {
                width: 44; height: 22; anchors.verticalCenter: parent.verticalCenter
                color: Theme.accent; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "播放全部"; color: "white"; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: if (root.songs.length > 0) root.playAll(root.songs) }
            }
        }
    }

    // 加载状态
    Text {
        anchors.centerIn: parent
        text: root.loading ? "加载中..." : "暂无歌曲"
        color: Theme.textMuted; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
        visible: root.songs.length === 0
    }

    // 歌曲列表
    ListView {
        id: songList
        anchors.top: topBar.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        clip: true
        visible: root.songs.length > 0
        model: root.songs
        delegate: Rectangle {
            width: parent.width; height: 26
            color: index % 2 === 0 ? Theme.bgPrimary : Theme.bgSecondary
            Row {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: (index + 1); color: Theme.textMuted; font.pixelSize: Theme.fontTiny; width: 14 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44; spacing: 0
                    Text { text: modelData.name; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width }
                    Text { text: modelData.artist; color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width }
                }
                Rectangle {
                    width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                    color: Theme.accent; radius: 11
                    Text { anchors.centerIn: parent; text: "▶"; color: "white"; font.pixelSize: 9 }
                    MouseArea { anchors.fill: parent; onClicked: root.playSong(modelData) }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.playSong(modelData) }
        }
    }

    // 加载歌单
    function load(id) {
        if (!id) return
        root.playlistId = id
        root.loading = true
        root.songs = []
        if (id === "daily") {
            ApiClient.dailyRecommend(function(d) {
                root.loading = false
                root.playlistName = "每日推荐"
                if (d.code === 200 && d.data && d.data.dailySongs) {
                    parseSongs(d.data.dailySongs)
                }
            }, function(e) { root.loading = false })
        } else {
            ApiClient.playlistDetail(id, function(d) {
                root.loading = false
                if (d.code === 200 && d.playlist) {
                    root.playlistName = d.playlist.name
                    parseSongs(d.playlist.tracks || [])
                }
            }, function(e) { root.loading = false })
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
                duration: s.dt || 0
            })
        }
        root.songs = list
    }
}
