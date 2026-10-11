import QtQuick 2.12

Rectangle {
    id: root
    width: 0
    height: 44
    radius: Theme.radiusLarge
    clip: true

    signal clicked()

    // 由调用方传入：icon 用可靠文本符号（不用 emoji），label 为文字
    property string icon: ""
    property string label: ""
    property color gradFrom: Theme.gradientFrom
    property color gradTo: Theme.gradientTo

    scale: mouseArea.pressed ? 0.95 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }

    // 渐变底 + 顶部高光（Canvas，避免依赖 QtGraphicalEffects）
    Canvas {
        id: gradCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var g = ctx.createLinearGradient(0, 0, width, 0)
            g.addColorStop(0, root.gradFrom)
            g.addColorStop(1, root.gradTo)
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)

            var h = ctx.createLinearGradient(0, 0, 0, height * 0.55)
            h.addColorStop(0, "#33FFFFFF")
            h.addColorStop(1, "#00FFFFFF")
            ctx.fillStyle = h
            ctx.fillRect(0, 0, width, height * 0.55)
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        // 圆形图标徽章
        Rectangle {
            width: 26
            height: 26
            radius: 13
            color: "#26FFFFFF"
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: root.icon
                color: "white"
                font.pixelSize: Theme.fontMedium
                font.bold: true
                font.family: Theme.fontFamily
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: "white"
            font.pixelSize: Theme.fontSmall
            font.bold: true
            font.family: Theme.fontFamily
            elide: Text.ElideRight
            width: parent.width - 34
            maximumLineCount: 1
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -3
        onClicked: root.clicked()
    }
}
