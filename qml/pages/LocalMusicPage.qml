import QtQuick 2.12
import "../components"

Rectangle {
    id: localPage
    objectName: "local"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal playLocal(var file)
    signal loaded(var item)

    property var files: []
    property bool loading: false
    property string selectedPath: ""

    Component.onCompleted: {
        localPage.loaded(localPage)
        localPage.refresh()
    }

    // 顶部栏
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
            anchors.rightMargin: 6
            spacing: 4

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
                    onClicked: localPage.backClicked()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "本地音乐"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontNormal
                font.bold: true
                font.family: Theme.fontFamily
            }

            Item { width: 1 }

            // 刷新按钮
            Rectangle {
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                color: refreshMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                radius: Theme.radiusSmall

                Text {
                    anchors.centerIn: parent
                    text: "↻"
                    color: Theme.primary
                    font.pixelSize: Theme.fontNormal
                    font.bold: true
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    onClicked: localPage.refresh()
                }
            }
        }
    }

    // 统计信息
    Rectangle {
        id: statsBar
        width: parent.width
        height: 20
        color: Theme.bgSecondary
        anchors.top: topBar.bottom

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: localPage.loading ? "扫描中..." : "共 " + localPage.files.length + " 首"
            color: Theme.textTertiary
            font.pixelSize: Theme.fontTiny
            font.family: Theme.fontFamily
        }
    }

    // 空状态
    Text {
        anchors.centerIn: parent
        text: localPage.loading ? "扫描中..." : "暂无本地音乐\n下载的歌曲会显示在这里"
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSmall
        font.family: Theme.fontFamily
        horizontalAlignment: Text.AlignHCenter
        visible: localPage.files.length === 0
    }

    // 文件列表
    ListView {
        id: fileList
        anchors.top: statsBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        visible: localPage.files.length > 0
        model: localPage.files

        delegate: Rectangle {
            width: parent.width
            height: 32
            color: index % 2 === 0 ? Theme.bgPrimary : Theme.bgCard

            scale: fileMouse.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: 60 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                // 音乐图标
                Rectangle {
                    width: 24
                    height: 24
                    radius: 4
                    color: Theme.withAlpha(Theme.primary, 0.15)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "♪"
                        color: Theme.primary
                        font.pixelSize: Theme.fontSmall
                        font.bold: true
                    }
                }

                // 文件信息
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 70
                    spacing: 0

                    Text {
                        text: modelData.name
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: modelData.sizeStr + "  " + modelData.ext.toUpperCase()
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.fontFamily
                    }
                }

                // 删除按钮
                Rectangle {
                    width: 24
                    height: 24
                    radius: 4
                    color: delMouse.pressed ? Theme.withAlpha(Theme.error, 0.3) : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.error
                        font.pixelSize: Theme.fontTiny
                        font.bold: true
                    }

                    MouseArea {
                        id: delMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        onClicked: {
                            localPage.selectedPath = modelData.path
                            deleteConfirm.visible = true
                        }
                    }
                }
            }

            MouseArea {
                id: fileMouse
                anchors.fill: parent
                onClicked: localPage.playLocal(modelData)
            }
        }
    }

    // 删除确认弹窗
    Rectangle {
        id: deleteConfirm
        width: parent.width
        height: parent.height
        color: "#80000000"
        visible: false
        z: 100

        Rectangle {
            width: 240
            height: 80
            radius: 8
            color: Theme.bgCard
            anchors.centerIn: parent
            border.color: Theme.borderLight
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text {
                    text: "确定删除这首歌曲？"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    Rectangle {
                        width: 70
                        height: 24
                        radius: 4
                        color: Theme.bgTertiary

                        Text {
                            anchors.centerIn: parent
                            text: "取消"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: deleteConfirm.visible = false
                        }
                    }

                    Rectangle {
                        width: 70
                        height: 24
                        radius: 4
                        color: Theme.error

                        Text {
                            anchors.centerIn: parent
                            text: "删除"
                            color: "white"
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                deleteConfirm.visible = false
                                localPage.deleteFile(localPage.selectedPath)
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: deleteConfirm.visible = false
        }
    }

    // ── 函数 ──
    function refresh() {
        localPage.loading = true
        ApiClient.localList(function(d) {
            localPage.loading = false
            if (d.code === 200 && d.files) {
                localPage.files = d.files
            }
        }, function(e) {
            localPage.loading = false
            console.log("[local] 扫描失败:", e)
        })
    }

    function deleteFile(path) {
        ApiClient.localDelete(path, function(d) {
            if (d.code === 200) {
                console.log("[local] 已删除:", path)
                localPage.refresh()
            }
        }, function(e) {
            console.log("[local] 删除失败:", e)
        })
    }
}
