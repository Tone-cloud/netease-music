import QtQuick 2.12
import "../components"

Rectangle {
    id: root
    objectName: "downloads"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal playLocal(string path, string name)

    property var downloads: []
    property bool loading: false

    // 顶部栏
    Rectangle {
        width: parent.width; height: 26
        color: Theme.bgSecondary
        Row {
            anchors.fill: parent; anchors.leftMargin: 6; spacing: 4
            Rectangle {
                width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "<"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.backClicked() }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "下载管理"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily }
            Item { width: 1 }
            Rectangle {
                width: 36; height: 20; anchors.verticalCenter: parent.verticalCenter
                color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "刷新"; color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: loadDownloads() }
            }
        }
    }

    // 空状态
    Text {
        anchors.top: parent.top; anchors.topMargin: 60
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.loading ? "加载中..." : "暂无下载歌曲"
        color: Theme.textMuted; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
        visible: root.downloads.length === 0
    }

    // 下载列表
    ListView {
        id: dlList
        anchors.top: parent.top; anchors.topMargin: 26
        anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        clip: true
        visible: root.downloads.length > 0
        model: root.downloads
        delegate: Rectangle {
            width: parent.width; height: 28
            color: index % 2 === 0 ? Theme.bgPrimary : Theme.bgSecondary
            Row {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 4
                Text { anchors.verticalCenter: parent.verticalCenter; text: "🎵"; font.pixelSize: 12 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; width: parent.width - 50; spacing: 0
                    Text { text: modelData.name; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width }
                    Text { text: modelData.artist + " · " + (modelData.size || ""); color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width }
                }
                Rectangle {
                    width: 24; height: 24; anchors.verticalCenter: parent.verticalCenter
                    color: Theme.accent; radius: 12
                    Text { anchors.centerIn: parent; text: "▶"; color: "white"; font.pixelSize: 9 }
                    MouseArea { anchors.fill: parent; onClicked: root.playLocal(modelData.path, modelData.name) }
                }
            }
        }
    }

    function loadDownloads() {
        root.loading = true
        root.downloads = []
        ApiClient.downloadList(function(d) {
            root.loading = false
            if (d.code === 200 && d.files) {
                root.downloads = d.files
            }
        }, function(e) { root.loading = false })
    }

    Component.onCompleted: loadDownloads()
}
