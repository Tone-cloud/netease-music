import QtQuick 2.12
import "../components"

Rectangle {
    id: root
    objectName: "search"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal playSong(var song)

    property var searchResults: []
    property string searchText: ""
    property bool searching: false

    // 搜索输入
    Rectangle {
        id: searchBar
        width: parent.width; height: 30
        color: Theme.bgSecondary
        Row {
            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 4
            Rectangle {
                width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "<"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.backClicked() }
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60; height: 24
                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
                    onAccepted: doSearch()
                }
                Text {
                    anchors.fill: parent; anchors.leftMargin: 1
                    text: "搜索歌曲、歌手、歌单"
                    color: Theme.textMuted; font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
                    verticalAlignment: Text.AlignVCenter
                    visible: searchInput.text.length === 0
                }
            }
            Rectangle {
                width: 36; height: 22; anchors.verticalCenter: parent.verticalCenter
                color: Theme.accent; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "搜索"; color: "white"; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: doSearch() }
            }
        }
    }

    // 搜索状态
    Text {
        id: statusText
        anchors.top: searchBar.bottom; anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 8
        text: root.searching ? "搜索中..." : (root.searchResults.length === 0 ? "输入关键词搜索" : "")
        color: Theme.textMuted; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
        visible: !root.searching && root.searchResults.length === 0 || root.searching
    }

    // 搜索结果列表
    ListView {
        id: resultList
        anchors.top: searchBar.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.margins: Theme.spacingS
        clip: true
        visible: root.searchResults.length > 0
        model: root.searchResults
        delegate: Rectangle {
            width: parent.width; height: 28
            color: index % 2 === 0 ? Theme.bgPrimary : Theme.bgSecondary
            Row {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (index + 1); color: Theme.textMuted; font.pixelSize: Theme.fontSmall
                    width: 16
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; width: parent.width - 50; spacing: 0
                    Text { text: modelData.name; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width }
                    Text { text: modelData.artist; color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width }
                }
                Rectangle {
                    width: 24; height: 24; anchors.verticalCenter: parent.verticalCenter
                    color: Theme.accent; radius: 12
                    Text { anchors.centerIn: parent; text: "▶"; color: "white"; font.pixelSize: 10 }
                    MouseArea { anchors.fill: parent; onClicked: root.playSong(modelData) }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.playSong(modelData) }
        }
    }

    function doSearch() {
        var kw = searchInput.text.trim()
        if (!kw) return
        root.searchText = kw
        root.searching = true
        root.searchResults = []
        ApiClient.search(kw, function(d) {
            root.searching = false
            if (d.code === 200 && d.result && d.result.songs) {
                var list = []
                for (var i = 0; i < Math.min(d.result.songs.length, 30); i++) {
                    var s = d.result.songs[i]
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
                root.searchResults = list
            }
        }, function(e) {
            root.searching = false
            statusText.text = "搜索失败: " + e
        })
    }
}
