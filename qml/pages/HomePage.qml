import QtQuick 2.12
import "../components"

Rectangle {
    id: homePage
    objectName: "home"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backButtonClicked()
    signal openPlaylist(string id)
    signal openSearch()
    signal openLogin()
    signal openUser()
    signal openToplist(int idx)
    signal openLocal()
    signal openDownload()
    signal openPersonalFM()
    signal playSong(var song)

    property bool isLoggedIn: false
    property string userName: ""
    property var recommendList: []
    property bool loadingRecommend: false
    property int tabIndex: 0

    onVisibleChanged: {
        if (visible) tabIndex = 0
    }

    function formatPlayCount(count) {
        if (!count || count <= 0) return ""
        if (count >= 100000000) return (count / 100000000).toFixed(1) + "亿"
        if (count >= 10000) return (count / 10000).toFixed(count >= 100000 ? 0 : 1) + "万"
        return String(count)
    }

    function recentQuickList() {
        var list = []
        for (var i = 0; i < Math.min(homePage.recommendList.length, 4); i++) {
            list.push(homePage.recommendList[i])
        }
        return list
    }

    Flickable {
        id: contentFlick
        anchors {
            top: parent.top
            bottom: tabBar.top
            left: parent.left
            right: parent.right
        }
        anchors.margins: Theme.spacingMedium
        contentWidth: width
        contentHeight: contentColumn.height
        clip: true
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.spacingSmall

            Column {
                width: parent.width
                spacing: Theme.spacingSmall

                Row {
                    width: parent.width
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: [
                            { label: "每日推荐", action: "daily", icon: "📅" },
                            { label: "漫游", action: "roam", icon: "🧭" },
                            { label: "雷达歌单", action: "radar", icon: "📡" },
                            { label: "电音专区", action: "electronic", icon: "🎧" }
                        ]
                        QuickActionCard {
                            width: (parent.width - Theme.spacingSmall * 3) / 4
                            height: 36
                            icon: modelData.icon
                            label: modelData.label
                            onClicked: {
                                if (modelData.action === "daily") homePage.openPlaylist("daily")
                                else if (modelData.action === "roam") homePage.openPlaylist("recent")
                                else if (modelData.action === "radar") homePage.openPersonalFM()
                                else if (modelData.action === "electronic") homePage.openToplist(0)
                            }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 6
                anchors.leftMargin: 2
                Text {
                    text: "推荐歌单"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontNormal
                    font.bold: true
                    font.family: Theme.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 1 }
                Text {
                    text: homePage.loadingRecommend ? "加载中..." : ""
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    color: refreshMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : Theme.bgCard
                    border.color: Theme.borderLight
                    border.width: 0.5
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.centerIn: parent
                        text: "↻"
                        color: Theme.primary
                        font.pixelSize: Theme.fontNormal
                        font.bold: true
                        font.family: Theme.fontFamily
                        rotation: homePage.loadingRecommend ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 500 } }
                    }
                    MouseArea {
                        id: refreshMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        onClicked: homePage.loadRecommend()
                    }
                }
            }

            Flickable {
                width: parent.width
                height: 82
                contentWidth: hRow.width
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                Row {
                    id: hRow
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: homePage.recommendList
                        PlaylistCard {
                            title: modelData.name || ""
                            coverUrl: modelData.picUrl || ""
                            badgeText: homePage.formatPlayCount(modelData.playcount)
                            showBadge: modelData.playcount > 0
                            onClicked: if (modelData.id) homePage.openPlaylist(String(modelData.id))
                        }
                    }
                    Text {
                        text: homePage.recommendList.length === 0 && !homePage.loadingRecommend ? "暂无推荐" : ""
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingSmall
                Rectangle {
                    width: parent.width
                    height: 24
                    color: "transparent"
                    Text {
                        text: "最近常听"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontNormal
                        font.bold: true
                        font.family: Theme.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    width: parent.width
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: homePage.recentQuickList()
                        Rectangle {
                            width: (parent.width - Theme.spacingSmall * 3) / 4
                            height: 54
                            radius: Theme.radiusSmall
                            color: Theme.bgCard
                            border.color: Theme.borderLight
                            border.width: 0.5
                            clip: true
                            Column {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 4
                                Image {
                                    width: parent.width
                                    height: 26
                                    source: modelData.picUrl || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }
                                Text {
                                    text: modelData.name || ""
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (modelData.id) homePage.openPlaylist(String(modelData.id))
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: tabBar
        width: parent.width
        height: Theme.tabBarHeight
        color: Theme.bgSecondary
        anchors.bottom: parent.bottom
        z: 10

        Rectangle {
            width: parent.width
            height: 1
            anchors.top: parent.top
            color: Theme.borderLight
        }

        Row {
            width: parent.width - 16
            anchors.centerIn: parent
            spacing: 4

            readonly property real exitButtonWidth: 24
            readonly property real tabButtonWidth: (width - exitButtonWidth - spacing * 4) / 4

            Rectangle {
                width: parent.exitButtonWidth
                height: 20
                radius: 10
                color: exitMouseArea.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                border.color: Theme.withAlpha(Theme.primary, 0.25)
                border.width: 1

                scale: exitMouseArea.pressed ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                Canvas {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = Theme.textSecondary
                        ctx.lineWidth = 1.4
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(7.5, 2)
                        ctx.lineTo(10, 2)
                        ctx.lineTo(10, 10)
                        ctx.lineTo(7.5, 10)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(7, 6)
                        ctx.lineTo(2.5, 6)
                        ctx.moveTo(4.5, 4)
                        ctx.lineTo(2.5, 6)
                        ctx.lineTo(4.5, 8)
                        ctx.stroke()
                    }
                }

                MouseArea {
                    id: exitMouseArea
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: homePage.backButtonClicked()
                }
            }

            Repeater {
                model: [
                    { label: "推荐", idx: 0 },
                    { label: "排行榜", idx: 1 },
                    { label: "搜索", idx: 2 },
                    { label: "我的", idx: 3 }
                ]

                TabButton {
                    width: parent.tabButtonWidth
                    height: 20
                    selected: homePage.tabIndex === modelData.idx
                    text: modelData.label
                    onClicked: {
                        homePage.tabIndex = modelData.idx
                        if (modelData.idx === 0) homePage.loadRecommend()
                        else if (modelData.idx === 1) homePage.openToplist(0)
                        else if (modelData.idx === 2) homePage.openSearch()
                        else if (modelData.idx === 3) homePage.openUser()
                    }
                }
            }
        }
    }

    function loadRecommend() {
        if (homePage.loadingRecommend) return
        homePage.loadingRecommend = true
        ApiClient.recommend(function(d) {
            homePage.loadingRecommend = false
            if (d.code === 200) {
                var list = d.recommend || d.playlists || []
                homePage.recommendList = list.slice(0, 12)
            }
        }, function(e) {
            homePage.loadingRecommend = false
            console.log("[home] 推荐歌单加载失败:", e)
        })
    }

    Component.onCompleted: loadRecommend()
}
