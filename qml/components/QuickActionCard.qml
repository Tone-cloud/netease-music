import QtQuick 2.12

Rectangle {
    id: root
    width: 0
    height: 44
    radius: Theme.radiusLarge
    clip: true
    // 兜底色：即使 gradient 不支持也显示品牌红，绝不出白框
    color: Theme.gradientFrom

    signal clicked()

    // 由调用方传入：icon 用可靠文本符号（不用 emoji），label 为文字
    property string icon: ""
    property string label: ""
    property color gradFrom: Theme.gradientFrom
    property color gradTo: Theme.gradientTo

    // 原生 QML 渐变（Rectangle.gradient 走场景图，不依赖 Canvas，真机渲染可靠）
    gradient: Gradient {
        GradientStop { position: 0.0; color: root.gradFrom }
        GradientStop { position: 1.0; color: root.gradTo }
    }

    scale: mouseArea.pressed ? 0.95 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }

    // 顶部高光（原生渐变覆盖，不依赖 Canvas）
    Rectangle {
        width: parent.width
        height: parent.height * 0.55
        anchors.top: parent.top
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#33FFFFFF" }
            GradientStop { position: 1.0; color: "#00FFFFFF" }
        }
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
