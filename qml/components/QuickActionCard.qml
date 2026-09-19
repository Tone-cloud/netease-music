import QtQuick 2.12

Rectangle {
    id: root
    width: 0
    height: 36
    color: Theme.bgCard
    radius: Theme.radiusLarge
    border.color: Theme.borderLight
    border.width: 0.5

    signal clicked()

    property string icon: ""
    property string label: ""

    scale: mouseArea.pressed ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }

    Column {
        anchors.centerIn: parent
        spacing: 1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            font.pixelSize: 12
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.textSecondary
            font.pixelSize: Theme.fontTiny
            font.family: Theme.fontFamily
            font.bold: true
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -3
        onClicked: root.clicked()
    }
}
