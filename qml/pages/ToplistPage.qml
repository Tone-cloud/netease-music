import QtQuick 2.12
import "../components"

Rectangle {
    id: toplistPage
    objectName: "toplist"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal openPlaylist(var id, int index)
    signal loaded(var item)

    property var toplists: []
    property bool loading: true

    Component.onCompleted: {
        ApiClient.toplist(function(d) {
            var list = []
            if (d.code === 200 && d.list) {
                for (var i = 0; i < d.list.length; i++) {
                    var item = d.list[i]
                    list.push({ name: item.name, id: item.id, desc: item.updateFrequency || "网易云音乐官方榜单" })
                }
            }
            toplistPage.toplists = list
            toplistPage.loading = false
            toplistPage.loaded(toplistPage)
        }, function() {
            toplistPage.loading = false
            toplistPage.loaded(toplistPage)
        })
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
                    onClicked: toplistPage.backClicked()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "排行榜"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontNormal
                font.bold: true
                font.family: Theme.fontFamily
            }
        }
    }

    // 排行榜列表
    ListView {
        id: toplistList
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        cacheBuffer: 200
        model: toplistPage.toplists

        delegate: Rectangle {
            width: toplistList.width
            height: 28
            color: index % 2 === 0 ? Theme.bgPrimary : Theme.bgCard

            scale: itemMouse.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: 60 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                // 序号
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: index + 1
                    color: index < 3 ? Theme.primary : Theme.textTertiary
                    font.pixelSize: Theme.fontSmall
                    font.bold: index < 3
                    font.family: Theme.fontFamily
                    width: 16
                    horizontalAlignment: Text.AlignHCenter
                }

                // 榜单信息
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
                    spacing: 0

                    Text {
                        text: modelData.name
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.bold: true
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: modelData.desc
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                // 箭头
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ">"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontNormal
                }
            }

            MouseArea {
                id: itemMouse
                anchors.fill: parent
                onClicked: toplistPage.openPlaylist(modelData.id, index)
            }
        }
    }
}
