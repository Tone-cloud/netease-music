import QtQuick 2.12
import "../components"

Rectangle {
    id: root
    objectName: "home"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal openPlaylist(string id)
    signal openSearch()
    signal openLogin()
    signal openUser()
    signal openToplist(int idx)
    signal playSong(var song)

    property bool isLoggedIn: false
    property string userName: ""

    Column {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        // 顶部栏
        Row {
            width: parent.width
            spacing: Theme.spacingS
            Rectangle {
                width: 24; height: 24; color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "<"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.backClicked() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "网易云音乐"; color: Theme.accent; font.pixelSize: Theme.fontLarge; font.bold: true
                font.family: Theme.fontFamily
            }
            Item { width: 1 }
            Rectangle {
                width: 50; height: 24; color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: root.isLoggedIn ? root.userName : "登录"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width - 8 }
                MouseArea { anchors.fill: parent; onClicked: root.isLoggedIn ? root.openUser() : root.openLogin() }
            }
        }

        // 搜索栏
        Rectangle {
            width: parent.width; height: 26
            color: Theme.bgCard; radius: Theme.radiusM
            Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; text: "🔍 搜索歌曲/歌手/歌单"; color: Theme.textMuted; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
            MouseArea { anchors.fill: parent; onClicked: root.openSearch() }
        }

        // 快捷入口
        Row {
            width: parent.width; spacing: Theme.spacingS
            Repeater {
                model: [
                    { label: "每日推荐", icon: "📅", action: "daily" },
                    { label: "排行榜", icon: "🏆", action: "toplist" },
                    { label: "下载", icon: "⬇️", action: "download" }
                ]
                Rectangle {
                    width: (parent.width - Theme.spacingS * 2) / 3
                    height: 36; color: Theme.bgCard; radius: Theme.radiusM
                    Column {
                        anchors.centerIn: parent; spacing: 1
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; font.pixelSize: 14 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.action === "daily") root.openPlaylist("daily")
                            else if (modelData.action === "toplist") root.openToplist(0)
                            else if (modelData.action === "download") root.openUser()
                        }
                    }
                }
            }
        }

        // 推荐歌单标题
        Text { text: "推荐歌单"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily }

        // 推荐歌单列表（横向滚动）
        Flickable {
            width: parent.width; height: 60
            contentWidth: hRow.width; contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            clip: true
            Row {
                id: hRow
                spacing: Theme.spacingS
                Repeater {
                    model: 6
                    Rectangle {
                        width: 55; height: 55
                        color: Theme.bgCard; radius: Theme.radiusM
                        border.color: Theme.divider; border.width: 0.5
                        Column {
                            anchors.centerIn: parent; spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "🎵"; font.pixelSize: 18 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "歌单" + (index + 1); color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.openPlaylist("rec_" + index) }
                    }
                }
            }
        }

        // 底部提示
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "提示：点击歌曲播放，支持歌词同步和下载"
            color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily
        }
    }
}
