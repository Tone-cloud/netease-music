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
    signal openDownload()
    signal playSong(var song)

    property bool isLoggedIn: false
    property string userName: ""
    property var recommendList: []
    property bool loadingRecommend: false
    property int tabIndex: 0  // 0=推荐, 1=排行, 2=搜索, 3=我的

    // 内容区域（给底部导航栏留空间，可滚动）
    Flickable {
        id: contentFlick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: tabBar.top
        anchors.margins: Theme.spacingM
        contentWidth: width
        contentHeight: contentColumn.height
        clip: true
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: contentColumn
            width: parent.width
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
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; text: root.isLoggedIn ? root.userName : "未登录"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width - 16 }
                MouseArea { anchors.fill: parent; onClicked: root.openUser() }
            }
        }

        // 搜索栏
        Rectangle {
            width: parent.width; height: 24
            color: Theme.bgCard; radius: Theme.radiusM
            Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; text: "搜索歌曲/歌手/歌单"; color: Theme.textMuted; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
            MouseArea { anchors.fill: parent; onClicked: root.openSearch() }
        }

        // 快捷入口
        Row {
            width: parent.width; spacing: Theme.spacingS
            Repeater {
                model: [
                    { label: "每日推荐", action: "daily" },
                    { label: "排行榜", action: "toplist" },
                    { label: "下载", action: "download" }
                ]
                Rectangle {
                    width: (parent.width - Theme.spacingS * 2) / 3
                    height: 32; color: Theme.bgCard; radius: Theme.radiusM
                    Text { anchors.centerIn: parent; text: modelData.label; color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.action === "daily") root.openPlaylist("daily")
                            else if (modelData.action === "toplist") root.openToplist(0)
                            else if (modelData.action === "download") root.openDownload()
                        }
                    }
                }
            }
        }

        // 推荐歌单标题
        Row {
            width: parent.width
            Text { text: "推荐歌单"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily }
            Item { width: 1 }
            Text { text: root.loadingRecommend ? "加载中..." : ""; color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily; anchors.verticalCenter: parent.verticalCenter }
        }

        // 推荐歌单列表（横向滚动）
        Flickable {
            width: parent.width; height: 64
            contentWidth: hRow.width; contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            clip: true
            Row {
                id: hRow
                spacing: Theme.spacingS
                Repeater {
                    model: root.recommendList
                    Rectangle {
                        width: 56; height: 64
                        color: Theme.bgCard; radius: Theme.radiusM
                        border.color: Theme.divider; border.width: 0.5
                        Column {
                            anchors.fill: parent; anchors.margins: 3; spacing: 2
                            Rectangle {
                                width: parent.width; height: 42
                                color: Theme.bgSecondary; radius: Theme.radiusS
                                Text { anchors.centerIn: parent; text: "歌单"; color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily }
                            }
                            Text { text: modelData.name || ""; color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily; elide: Text.ElideRight; width: parent.width; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; maximumLineCount: 2 }
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (modelData.id) root.openPlaylist(String(modelData.id)) }
                    }
                }
                // 空状态
                Text {
                    text: root.recommendList.length === 0 && !root.loadingRecommend ? "暂无推荐" : ""
                    color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
    }

    // 底部导航栏（参考 BiliPocket）
    Rectangle {
        id: tabBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 28
        color: Theme.bgSecondary
        border.color: Theme.divider; border.width: 0.5

        Row {
            anchors.fill: parent
            Repeater {
                model: [
                    { label: "推荐", idx: 0 },
                    { label: "排行", idx: 1 },
                    { label: "搜索", idx: 2 },
                    { label: "我的", idx: 3 }
                ]
                Rectangle {
                    width: parent.width / 4
                    height: parent.height
                    color: root.tabIndex === modelData.idx ? Theme.bgCard : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: root.tabIndex === modelData.idx ? Theme.accent : Theme.textSecondary
                        font.pixelSize: Theme.fontTiny
                        font.bold: root.tabIndex === modelData.idx
                        font.family: Theme.fontFamily
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.tabIndex = modelData.idx
                            if (modelData.idx === 0) { /* 推荐，当前页 */ }
                            else if (modelData.idx === 1) root.openToplist(0)
                            else if (modelData.idx === 2) root.openSearch()
                            else if (modelData.idx === 3) root.openUser()
                        }
                    }
                }
            }
        }
    }

    function loadRecommend() {
        if (root.loadingRecommend) return
        root.loadingRecommend = true
        ApiClient.recommend(function(d) {
            root.loadingRecommend = false
            if (d.code === 200) {
                var list = d.recommend || d.playlists || []
                root.recommendList = list.slice(0, 12)
            }
        }, function(e) {
            root.loadingRecommend = false
        })
    }

    Component.onCompleted: loadRecommend()
}
