import QtQuick 2.12

Rectangle {
    id: root
    width: 72
    height: 88
    color: Theme.bgCard
    radius: Theme.radiusMedium
    border.color: Theme.borderLight
    border.width: 0.5

    signal clicked()

    property string title: ""
    property string coverUrl: ""
    property string badgeText: ""
    property bool showBadge: false

    scale: mouseArea.pressed ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }

    Column {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        Rectangle {
            width: parent.width
            height: 56
            radius: Theme.radiusSmall
            clip: true
            color: Theme.bgSecondary

            Image {
                anchors.fill: parent
                source: root.coverUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 100
                sourceSize.height: 100
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 2
                anchors.rightMargin: 2
                width: badgeTextLabel.width + 8
                height: 14
                radius: 7
                color: "#99000000"
                visible: root.showBadge && root.badgeText.length > 0

                Text {
                    id: badgeTextLabel
                    anchors.centerIn: parent
                    text: root.badgeText
                    color: "white"
                    font.pixelSize: 9
                    font.family: Theme.fontFamily
                    font.bold: true
                }
            }
        }

        Text {
            text: root.title
            color: Theme.textSecondary
            font.pixelSize: Theme.fontTiny
            font.family: Theme.fontFamily
            elide: Text.ElideRight
            width: parent.width
            maximumLineCount: 1
            wrapMode: Text.NoWrap
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -3
        onClicked: root.clicked()
    }
}
