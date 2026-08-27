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
    signal openDownloads()
    signal openLogin()
    signal logout()

    property var userInfo: null
    property var userPlaylists: []
    property bool loading: false
    readonly property bool isLoggedIn: userPage.userInfo !== null

    // ── 顶部栏 ──
    Rectangle {
        id: topBar
        width: parent.width
        height: Theme.titleBarHeight
        color: Theme.bgSecondary

        // 顶部边线
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

            // 返回按钮
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

                // 占位头像
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

                // 登录提示卡片
                Rectangle {
                    width: parent.width
                    height: 60
                    color: Theme.bgCard
                    radius: Theme.radiusLarge
                    border.color: Theme.borderLight
                    border.width: 0.5

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Text {
                            text: "浏览器访问以下地址登录："
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
                            text: "支持 Cookies 导入，登录成功后自动保存。"
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

                // 用户信息卡片
                Rectangle {
                    width: parent.width
                    height: 56
                    color: Theme.bgCard
                    radius: Theme.radiusLarge
                    border.color: Theme.borderLight
                    border.width: 0.5

                    Row {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        // 真实头像（圆形裁剪）
                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
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
                                sourceSize.width: 80
                                sourceSize.height: 80
                            }

                            // 加载失败时显示首字母
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

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: userPage.userInfo ? userPage.userInfo.nickname : ""
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontNormal
                                font.bold: true
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                width: parent.parent.width - 60
                            }

                            Text {
                                visible: userPage.userInfo && userPage.userInfo.level && userPage.userInfo.level !== "?"
                                text: userPage.userInfo ? ("Lv." + userPage.userInfo.level) : ""
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontTiny
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }

                // 功能入口
                Repeater {
                    model: [
                        { label: "我的歌单", action: "playlists", icon: "📋" },
                        { label: "下载管理", action: "downloads", icon: "⬇" },
                        { label: "退出登录", action: "logout", icon: "↩" }
                    ]

                    Rectangle {
                        width: parent.width
                        height: 26
                        color: Theme.bgCard
                        radius: Theme.radiusMedium
                        border.color: Theme.borderLight
                        border.width: 0.5

                        scale: funcMouse.pressed ? 0.98 : 1.0
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

                            Item { width: parent.width - 100 }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ">"
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontNormal
                            }
                        }

                        MouseArea {
                            id: funcMouse
                            anchors.fill: parent
                            onClicked: {
                                if (modelData.action === "downloads") userPage.openDownloads()
                                else if (modelData.action === "logout") userPage.logout()
                                else if (modelData.action === "playlists") loadUserPlaylists()
                            }
                        }
                    }
                }

                // 我的歌单列表
                Column {
                    width: parent.width
                    spacing: Theme.spacingSmall
                    visible: userPage.userPlaylists.length > 0

                    Text {
                        text: "我的歌单"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.bold: true
                        font.family: Theme.fontFamily
                    }

                    ListView {
                        width: parent.width
                        height: Math.min(userPage.userPlaylists.length * 36, 108)
                        clip: true
                        model: userPage.userPlaylists

                        delegate: Rectangle {
                            width: parent.width
                            height: 34
                            color: index % 2 === 0 ? Theme.bgCard : Theme.bgSecondary
                            radius: Theme.radiusSmall

                            Row {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 8

                                // 歌单封面
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

    Component.onCompleted: if (userPage.userInfo) loadUserPlaylists()
}
