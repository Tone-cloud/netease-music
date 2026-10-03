import QtQuick 2.12
import "../components"

Rectangle {
    id: userPage
    objectName: "user"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal openPlaylist(string id)
    signal openLocal()
    signal openLogin()
    signal logout()

    property var userInfo: null
    property var userDetail: null
    property var userLevel: null
    property var userPlaylists: []
    property bool loading: false
    readonly property bool isLoggedIn: userPage.userInfo !== null
    readonly property string vipLabel: {
        var t = 0, lv = 0, redLv = 0, assoc = false
        if (userPage.userDetail) {
            var p = userPage.userDetail.profile || {}
            t = p.vipType || 0
            lv = p.redVipLevel || 0
            var r = p.vipRights || {}
            assoc = !!r.associator
            redLv = r.redVipLevel || 0
            if (!t && userPage.userDetail.account) t = userPage.userDetail.account.vipType || 0
        }
        if (!t && userPage.userInfo) t = userPage.userInfo.vipType || 0
        if (t >= 11 || lv >= 2 || redLv >= 2) return "黑胶SVIP"
        if (t > 0 || lv > 0 || redLv > 0 || assoc) return "黑胶VIP"
        return ""
    }
    readonly property bool isVip: userPage.vipLabel.length > 0

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
            spacing: 6

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
                    onClicked: userPage.backClicked()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "个人中心"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontNormal
                font.bold: true
                font.family: Theme.fontFamily
            }
        }
    }

    // ── 内容区（可滚动）──
    Flickable {
        id: flick
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        contentWidth: width
        contentHeight: contentCol.height
        clip: true

        Column {
            id: contentCol
            width: parent.width
            spacing: Theme.spacingMedium
            padding: Theme.spacingMedium

            // ── 未登录 ──
            Column {
                width: parent.width
                spacing: Theme.spacingMedium
                visible: !userPage.isLoggedIn

                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: Theme.bgTertiary
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "?"
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontLarge
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                }

                Text {
                    text: "未登录"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontNormal
                    font.bold: true
                    font.family: Theme.fontFamily
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Rectangle {
                    width: parent.width
                    height: 66
                    color: Theme.bgCard
                    radius: Theme.radiusLarge
                    border.color: Theme.borderLight
                    border.width: 0.5

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Text {
                            text: "电脑浏览器访问以下地址登录："
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                        }

                        Rectangle {
                            width: parent.width
                            height: 18
                            color: Theme.bgInput
                            radius: Theme.radiusSmall

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                text: "http://词典笔IP:8667/verify.html"
                                color: Theme.primary
                                font.pixelSize: Theme.fontTiny
                                font.family: Theme.fontFamily
                            }
                        }

                        Text {
                            text: "只需复制粘贴 MUSIC_U，无需手机验证"
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                        }
                    }
                }
            }

            // ── 已登录 ──
            Column {
                width: parent.width
                spacing: Theme.spacingMedium
                visible: userPage.isLoggedIn

                // ══ 用户信息卡片 ══
                Rectangle {
                    width: parent.width
                    height: 96
                    color: Theme.bgCard
                    radius: Theme.radiusLarge
                    border.color: Theme.borderLight
                    border.width: 0.5

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10

                        Row {
                            width: parent.width
                            spacing: 10

                            // 头像
                            Rectangle {
                                width: 48
                                height: 48
                                radius: 24
                                clip: true
                                color: Theme.bgTertiary
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: avatarImage
                                    anchors.fill: parent
                                    source: userPage.userInfo ? (userPage.userInfo.avatarUrl || userPage.userInfo.avatarImgUrl || "") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 96
                                    sourceSize.height: 96
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: userPage.userInfo && userPage.userInfo.nickname ? userPage.userInfo.nickname.charAt(0) : "U"
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontMedium
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    visible: !avatarImage.status || avatarImage.status === Image.Error
                                }
                            }

                            // 昵称 + 等级 + VIP
                            Column {
                                width: parent.width - 58
                                spacing: 3
                                anchors.verticalCenter: parent.verticalCenter

                                // 昵称行
                                Row {
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        width: parent.width
                                            - (levelBadge.visible ? levelBadge.width + 6 : 0)
                                            - (vipBadge.visible ? vipBadge.width + 6 : 0)
                                        text: userPage.userInfo ? userPage.userInfo.nickname : ""
                                        color: Theme.textPrimary
                                        font.pixelSize: Theme.fontNormal
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    // 等级标签
                                    Rectangle {
                                        id: levelBadge
                                        visible: userPage.userLevel && userPage.userLevel.level
                                        width: levelText.width + 10
                                        height: 14
                                        radius: 7
                                        color: Theme.withAlpha(Theme.primary, 0.15)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            id: levelText
                                            anchors.centerIn: parent
                                            text: "Lv." + (userPage.userLevel ? userPage.userLevel.level : 0)
                                            color: Theme.primary
                                            font.pixelSize: Theme.fontTiny
                                            font.family: Theme.fontFamily
                                            font.bold: true
                                        }
                                    }

                                    // VIP 标签
                                    Rectangle {
                                        id: vipBadge
                                        visible: userPage.isVip
                                        width: vipText.width + 10
                                        height: 14
                                        radius: 7
                                        color: "#D4AF37"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            id: vipText
                                            anchors.centerIn: parent
                                            text: userPage.vipLabel
                                            color: "white"
                                            font.pixelSize: Theme.fontTiny
                                            font.family: Theme.fontFamily
                                            font.bold: true
                                        }
                                    }
                                }

                                // 签名
                                Text {
                                    text: userPage.userDetail && userPage.userDetail.profile ? (userPage.userDetail.profile.signature || "这个人很懒，什么都没写") : "加载中..."
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    width: parent.width
                                    maximumLineCount: 1
                                }

                                // 数据统计：关注 / 粉丝 / 累计听歌
                                Row {
                                    width: parent.width
                                    spacing: 4

                                    Text {
                                        width: parent.width / 3
                                        text: "关注 " + (userPage.userDetail && userPage.userDetail.profile ? userPage.userDetail.profile.follows : 0)
                                        color: Theme.textTertiary
                                        font.pixelSize: Theme.fontTiny
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width / 3
                                        text: "粉丝 " + (userPage.userDetail && userPage.userDetail.profile ? userPage.userDetail.profile.followeds : 0)
                                        color: Theme.textTertiary
                                        font.pixelSize: Theme.fontTiny
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width / 3
                                        text: "听歌 " + (userPage.userLevel && userPage.userLevel.listenSongs ? userPage.userLevel.listenSongs : 0) + "首"
                                        color: Theme.textTertiary
                                        font.pixelSize: Theme.fontTiny
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                    }
                                }

                                // VIP 状态
                                Text {
                                    text: userPage.isVip ? "已开通「" + userPage.vipLabel + "」· 会员专享曲库/无损音质" : "未开通会员"
                                    color: userPage.isVip ? "#D4AF37" : Theme.textTertiary
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }
                    }
                }

                // ══ 功能入口 ══
                Repeater {
                    model: [
                        { label: "本地音乐", action: "local", icon: "🎵" },
                        { label: "退出登录", action: "logout", icon: "↩" }
                    ]

                    Rectangle {
                        width: parent.width
                        height: 28
                        color: Theme.bgCard
                        radius: Theme.radiusMedium
                        border.color: Theme.borderLight
                        border.width: 0.5

                        Behavior on scale { NumberAnimation { duration: 80 } }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon
                                color: Theme.primary
                                font.pixelSize: Theme.fontSmall
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: modelData.action === "logout" ? Theme.error : Theme.textPrimary
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.fontFamily
                            }

                            Item { width: 1 }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ">"
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontNormal
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressedChanged: parent.scale = pressed ? 0.98 : 1.0
                            onClicked: {
                                if (modelData.action === "local") userPage.openLocal()
                                else if (modelData.action === "logout") userPage.logout()
                            }
                        }
                    }
                }

                // ══ 我的歌单 ══
                Column {
                    width: parent.width
                    spacing: Theme.spacingSmall

                    Text {
                        text: "我的歌单 (" + userPage.userPlaylists.length + ")"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.bold: true
                        font.family: Theme.fontFamily
                    }

                    ListView {
                        width: parent.width
                        height: Math.min(userPage.userPlaylists.length * 38, 152)
                        clip: true
                        model: userPage.userPlaylists

                        delegate: Rectangle {
                            width: parent.width
                            height: 36
                            color: index % 2 === 0 ? Theme.bgCard : Theme.bgSecondary
                            radius: Theme.radiusSmall

                            Row {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 8

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: Theme.radiusSmall
                                    clip: true
                                    color: Theme.bgTertiary
                                    anchors.verticalCenter: parent.verticalCenter

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.coverImgUrl || modelData.picUrl || ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize.width: 48
                                        sourceSize.height: 48
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    width: parent.width - 40
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: userPage.openPlaylist(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    function loadUserPlaylists() {
        if (!userPage.userInfo || !userPage.userInfo.userId) return
        userPage.loading = true
        ApiClient.userPlaylist(userPage.userInfo.userId, function(d) {
            userPage.loading = false
            if (d.code === 200 && d.playlist) {
                var list = []
                for (var i = 0; i < Math.min(d.playlist.length, 20); i++) {
                    list.push({
                        id: d.playlist[i].id,
                        name: d.playlist[i].name,
                        coverImgUrl: d.playlist[i].coverImgUrl || d.playlist[i].picUrl || ""
                    })
                }
                userPage.userPlaylists = list
            }
        }, function(e) { userPage.loading = false })
    }

    function loadUserDetail() {
        if (!userPage.userInfo || !userPage.userInfo.userId) return
        var uid = userPage.userInfo.userId
        ApiClient.userDetail(uid, function(d) {
            if (d.code === 200) userPage.userDetail = d
        }, function(e) { console.log("[user] detail error:", e) })
        ApiClient.userLevel(function(d) {
            if (d.code === 200 && d.data) userPage.userLevel = d.data
        }, function(e) { console.log("[user] level error:", e) })
    }

    Component.onCompleted: {
        if (userPage.userInfo) {
            loadUserPlaylists()
            loadUserDetail()
        }
    }
}
