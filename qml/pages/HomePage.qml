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
    signal openSearchWithKeyword(string kw)
    signal openLogin()
    signal openUser()
    signal openToplist(int idx)
    signal openLocal()
    signal openDownload()
    signal openPersonalFM()
    signal playSong(var song)
    signal showToast(string msg)

    property bool isLoggedIn: false
    property string userName: ""
    property var recommendList: []
    property bool loadingRecommend: false
    property int tabIndex: 0
    // 推荐歌单最后成功加载的日期（用于跨天自动刷新；插件常驻内存不会重建页面）
    property string lastRecommendDay: ""

    function todayStr() {
        var d = new Date()
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    onVisibleChanged: {
        if (visible) {
            tabIndex = 0
            // 重新进入首页：若跨天或列表为空则自动刷新推荐歌单，
            // 避免词典笔插件常驻内存导致每天都显示旧列表
            if (homePage.recommendList.length === 0 || todayStr() !== homePage.lastRecommendDay) {
                homePage.loadRecommend()
            }
        }
    }

    function formatPlayCount(count) {
        if (!count || count <= 0) return ""
        if (count >= 100000000) return (count / 100000000).toFixed(1) + "亿"
        if (count >= 10000) return (count / 10000).toFixed(count >= 100000 ? 0 : 1) + "万"
        return String(count)
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

            // ── 第一行：快捷入口 ──
            Row {
                width: parent.width
                spacing: Theme.spacingSmall
                Repeater {
                    model: [
                        { label: "每日推荐", action: "daily", icon: "日" },
                        { label: "私人FM", action: "fm", icon: "FM" }
                    ]
                    QuickActionCard {
                        width: (parent.width - Theme.spacingSmall) / 2
                        height: 44
                        icon: modelData.icon
                        label: modelData.label
                        gradFrom: modelData.action === "daily" ? Theme.gradientFrom : Theme.gradientDeep
                        gradTo: modelData.action === "daily" ? Theme.gradientTo : Theme.primary
                        onClicked: {
                            if (modelData.action === "daily") homePage.openPlaylist("daily")
                            else if (modelData.action === "fm") homePage.openPlaylist("fm")
                        }
                    }
                }
            }

            // ── 第二行：推荐歌单标题 ──
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
                    width: 52
                    horizontalAlignment: Text.AlignRight
                    text: homePage.loadingRecommend ? "加载中..." : ""
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: refreshMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : Theme.bgCard
                    border.color: Theme.borderLight
                    border.width: 0.5
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        id: refreshIcon
                        anchors.centerIn: parent
                        text: "↻"
                        color: homePage.loadingRecommend ? Theme.primary : Theme.textSecondary
                        font.pixelSize: Theme.fontNormal
                        font.bold: true
                        font.family: Theme.fontFamily
                        transformOrigin: Item.Center

                        NumberAnimation on rotation {
                            running: homePage.loadingRecommend
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                        }

                        Connections {
                            target: homePage
                            onLoadingRecommendChanged: {
                                if (!homePage.loadingRecommend) refreshIcon.rotation = 0
                            }
                        }
                    }
                    MouseArea {
                        id: refreshMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        onClicked: homePage.loadRecommend(function(ok) {
                            homePage.showToast(ok ? "推荐内容已刷新" : "刷新失败，请检查网络后重试")
                        })
                    }
                }
            }

            // ── 推荐歌单横向滚动 ──
            Flickable {
                width: parent.width
                height: 96
                contentWidth: hRow.width
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                Row {
                    id: hRow
                    spacing: 8
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
        }
    }

    // ── 底部导航栏 ──
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

                scale: exitMouseArea.pressed ? 0.9 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                // 退出键：真机 Canvas 渲染不可靠，改用必定可渲染的文本符号
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: exitMouseArea.pressed ? "white" : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: 80 } }
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

    function loadRecommend(cb) {
        if (homePage.loadingRecommend) return
        homePage.loadingRecommend = true
        ApiClient.recommend(function(d) {
            homePage.loadingRecommend = false
            if (d && d.code === 200) {
                var list = d.recommend || d.playlists || []
                homePage.recommendList = list.slice(0, 12)
                homePage.lastRecommendDay = homePage.todayStr()
                if (cb) cb(true)
            } else {
                console.log("[home] 推荐歌单返回异常:", JSON.stringify(d))
                if (cb) cb(false)
            }
        }, function(e) {
            homePage.loadingRecommend = false
            console.log("[home] 推荐歌单加载失败:", e)
            if (cb) cb(false)
        })
    }

    Component.onCompleted: {
        loadRecommend()
    }
}
