import QtQuick 2.12

Rectangle {
    id: root
    width: 48
    height: 20
    radius: Theme.radiusRound
    color: mouseArea.pressed ? Theme.withAlpha(Theme.primary, 0.2) : (selected ? Theme.withAlpha(Theme.primary, 0.15) : "transparent")
    border.width: 0

    signal clicked()

    property bool selected: false
    property string text: ""

    scale: mouseArea.pressed ? 0.92 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }
    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
        text: root.text
        color: root.selected ? Theme.primary : Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        font.bold: root.selected
        anchors.centerIn: parent

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -4
        onClicked: root.clicked()
    }
}
