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
    signal openRecent()
    signal playSong(var song)

    property bool isLoggedIn: false
    property string userName: ""
    property var recommendList: []
    property bool loadingRecommend: false
    property int tabIndex: 0  // 0=推荐

    // 格式化播放量
    function formatPlayCount(count) {
        if (!count || count <= 0) return ""
        if (count >= 100000000) return (count / 100000000).toFixed(1) + "亿"
        if (count >= 10000) return (count / 10000).toFixed(count >= 100000 ? 0 : 1) + "万"
        return String(count)
    }

    // ── 内容区 (无标题栏，高度 = 170 - 26 = 144px) ──
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

            // 快捷入口（两行）
            Column {
                width: parent.width
                spacing: Theme.spacingSmall

                // 第一行：每日推荐、私人FM、最近播放
                Row {
                    width: parent.width
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: [
                            { label: "每日推荐", action: "daily", icon: "📅" },
                            { label: "私人FM", action: "fm", icon: "📻" },
                            { label: "最近播放", action: "recent", icon: "⏱" }
                        ]
                        Rectangle {
                            width: (parent.width - Theme.spacingSmall * 2) / 3
                            height: 36
                            color: Theme.bgCard
                            radius: Theme.radiusLarge
                            border.color: Theme.borderLight
                            border.width: 0.5

                            scale: quickMouse.pressed ? 0.96 : 1.0
                            Behavior on scale { NumberAnimation { duration: 80 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: quickMouse
                                anchors.fill: parent
                                anchors.margins: -3
                                onClicked: {
                                    if (modelData.action === "daily") homePage.openPlaylist("daily")
                                    else if (modelData.action === "fm") homePage.openPersonalFM()
                                    else if (modelData.action === "recent") homePage.openRecent()
                                }
                            }
                        }
                    }
                }

                // 第二行：排行榜、本地音乐、我的
                Row {
                    width: parent.width
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: [
                            { label: "排行榜", action: "toplist", icon: "🏆" },
                            { label: "本地音乐", action: "local", icon: "🎵" },
                            { label: "我的", action: "user", icon: "👤" }
                        ]
                        Rectangle {
                            width: (parent.width - Theme.spacingSmall * 2) / 3
                            height: 36
                            color: Theme.bgCard
                            radius: Theme.radiusLarge
                            border.color: Theme.borderLight
                            border.width: 0.5

                            scale: quickMouse2.pressed ? 0.96 : 1.0
                            Behavior on scale { NumberAnimation { duration: 80 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    font.pixelSize: 12
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: quickMouse2
                                anchors.fill: parent
                                anchors.margins: -3
                                onClicked: {
                                    if (modelData.action === "toplist") homePage.openToplist(0)
                                    else if (modelData.action === "local") homePage.openLocal()
                                    else if (modelData.action === "user") homePage.openUser()
                                }
                            }
                        }
                    }
                }
            }

            // 推荐歌单标题（带刷新按钮）
            Row {
                width: parent.width
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
                Item { width: 1; height: 1 }
                // 刷新按钮
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
                        onClicked: {
                            console.log("[home] 刷新推荐歌单")
                            homePage.loadRecommend()
                        }
                    }
                }
            }

            // 推荐歌单列表（横向滚动，带封面）
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

                        Rectangle {
                            width: 72
                            height: 88
                            color: Theme.bgCard
                            radius: Theme.radiusMedium
                            border.color: Theme.borderLight
                            border.width: 0.5

                            scale: playlistMouse.pressed ? 0.96 : 1.0
                            Behavior on scale { NumberAnimation { duration: 80 } }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 4

                                // 封面图
                                Rectangle {
                                    width: parent.width
                                    height: 56
                                    radius: Theme.radiusSmall
                                    clip: true
                                    color: Theme.bgSecondary

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.picUrl || ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize.width: 100
                                        sourceSize.height: 100
                                    }

                                    // 播放数角标（优化：更大字体，显示所有播放量）
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: 2
                                        anchors.rightMargin: 2
                                        width: playCountText.width + 8
                                        height: 14
                                        radius: 7
                                        color: "#99000000"
                                        visible: modelData.playcount > 0

                                        Text {
                                            id: playCountText
                                            anchors.centerIn: parent
                                            text: homePage.formatPlayCount(modelData.playcount)
                                            color: "white"
                                            font.pixelSize: 9
                                            font.family: Theme.fontFamily
                                            font.bold: true
                                        }
                                    }
                                }

                                // 歌单名称（单行，bili风格）
                                Text {
                                    text: modelData.name || ""
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    width: parent.width
                                    maximumLineCount: 1
                                    wrapMode: Text.NoWrap
                                }
                            }

                            MouseArea {
                                id: playlistMouse
                                anchors.fill: parent
                                anchors.margins: -3
                                onClicked: if (modelData.id) homePage.openPlaylist(String(modelData.id))
                            }
                        }
                    }

                    // 空状态
                    Text {
                        text: homePage.recommendList.length === 0 && !homePage.loadingRecommend ? "暂无推荐" : ""
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // ── 底部标签栏 (bili风格：退出按钮在最左) ──
    Rectangle {
        id: tabBar
        width: parent.width
        height: Theme.tabBarHeight
        color: Theme.bgSecondary
        anchors.bottom: parent.bottom
        z: 10

        // 顶部边线
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
            readonly property real tabButtonWidth: (width - exitButtonWidth - spacing * 3) / 3

            // 退出按钮（最左端）
            Rectangle {
                width: parent.exitButtonWidth
                height: 20
                radius: 10
                color: exitMouseArea.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                border.color: Theme.withAlpha(Theme.primary, 0.25)
                border.width: 1

                scale: exitMouseArea.pressed ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }
                Behavior on color { ColorAnimation { duration: 100 } }

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

                        // 退出图标（门+箭头）
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

            // Tab 按钮
            Repeater {
                model: [
                    { label: "推荐", idx: 0 },
                    { label: "搜索", idx: 2 },
                    { label: "我的", idx: 3 }
                ]

                Rectangle {
                    width: parent.tabButtonWidth
                    height: 20
                    radius: 10
                    color: {
                        if (tabMouseArea.pressed) return Theme.withAlpha(Theme.primary, 0.2)
                        return homePage.tabIndex === modelData.idx
                            ? Theme.withAlpha(Theme.primary, 0.15)
                            : "transparent"
                    }

                    scale: tabMouseArea.pressed ? 0.92 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        text: modelData.label
                        color: homePage.tabIndex === modelData.idx ? Theme.primary : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSmall
                        font.bold: homePage.tabIndex === modelData.idx
                        anchors.centerIn: parent

                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    MouseArea {
                        id: tabMouseArea
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: {
                            homePage.tabIndex = modelData.idx
                            if (modelData.idx === 0) {
                                // 推荐，当前页，再次点击刷新
                                homePage.loadRecommend()
                            } else if (modelData.idx === 2) {
                                homePage.openSearch()
                            } else if (modelData.idx === 3) {
                                homePage.openUser()
                            }
                        }
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
                console.log("[home] 推荐歌单加载完成，共", homePage.recommendList.length, "个")
            }
        }, function(e) {
            homePage.loadingRecommend = false
            console.log("[home] 推荐歌单加载失败:", e)
        })
    }

    Component.onCompleted: loadRecommend()
}
