import QtQuick 2.12
import "../components"

Rectangle {
    id: root
    objectName: "user"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal openPlaylist(string id)
    signal openDownloads()
    signal logout()

    property var userInfo: null
    property var userPlaylists: []
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
            Text { anchors.verticalCenter: parent.verticalCenter; text: "个人中心"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily }
        }
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Theme.spacingM
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        spacing: Theme.spacingM

        // 用户信息
        Row {
            width: parent.width; spacing: Theme.spacingM
            Rectangle {
                width: 44; height: 44; radius: 22
                color: Theme.accent
                Text { anchors.centerIn: parent; text: root.userInfo ? (root.userInfo.nickname ? root.userInfo.nickname.charAt(0) : "U") : "U"; color: "white"; font.pixelSize: 18; font.bold: true }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: 2
                Text { text: root.userInfo ? root.userInfo.nickname : "未登录"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily }
                Text { text: root.userInfo ? ("等级: Lv." + (root.userInfo.level || "?")) : ""; color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily }
            }
        }

        // 功能入口
        Repeater {
            model: [
                { label: "我的歌单", icon: "📁", action: "playlists" },
                { label: "下载管理", icon: "⬇️", action: "downloads" },
                { label: "退出登录", icon: "🚪", action: "logout" }
            ]
            Rectangle {
                width: parent.width; height: 28
                color: Theme.bgCard; radius: Theme.radiusS
                Row {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; font.pixelSize: 14 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily; leftPadding: 8 }
                    Item { width: 1 }
                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; text: ">"; color: Theme.textMuted; font.pixelSize: Theme.fontNormal }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (modelData.action === "downloads") root.openDownloads()
                        else if (modelData.action === "logout") root.logout()
                        else if (modelData.action === "playlists") loadUserPlaylists()
                    }
                }
            }
        }

        // 我的歌单列表
        Text { text: "我的歌单"; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; font.bold: true; font.family: Theme.fontFamily; visible: root.userPlaylists.length > 0 }

        ListView {
            width: parent.width; height: 60
            clip: true
            visible: root.userPlaylists.length > 0
            model: root.userPlaylists
            delegate: Rectangle {
                width: parent.width; height: 22
                color: index % 2 === 0 ? Theme.bgPrimary : Theme.bgSecondary
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 6; text: modelData.name; color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width - 12 }
                MouseArea { anchors.fill: parent; onClicked: root.openPlaylist(modelData.id) }
            }
        }
    }

    function loadUserPlaylists() {
        if (!root.userInfo || !root.userInfo.userId) return
        root.loading = true
        ApiClient.userPlaylist(root.userInfo.userId, function(d) {
            root.loading = false
            if (d.code === 200 && d.playlist) {
                var list = []
                for (var i = 0; i < Math.min(d.playlist.length, 20); i++) {
                    list.push({ id: d.playlist[i].id, name: d.playlist[i].name })
                }
                root.userPlaylists = list
            }
        }, function(e) { root.loading = false })
    }

    Component.onCompleted: if (root.userInfo) loadUserPlaylists()
}
