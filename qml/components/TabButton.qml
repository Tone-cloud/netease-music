import QtQuick 2.12

Rectangle {
    id: root
    width: 48
    height: 20
    radius: Theme.radiusRound
    color: mouseArea.pressed ? Theme.withAlpha(Theme.primary, 0.45) : (selected ? Theme.withAlpha(Theme.primary, 0.22) : "transparent")
    border.width: 0

    signal clicked()

    property bool selected: false
    property string text: ""

    scale: mouseArea.pressed ? 0.9 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }
    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
        text: root.text
        color: mouseArea.pressed ? "white" : (root.selected ? Theme.primary : Theme.textSecondary)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        font.bold: root.selected || mouseArea.pressed
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
