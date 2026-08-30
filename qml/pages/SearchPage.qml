import QtQuick 2.12
import "../components"

Rectangle {
    id: searchPage
    objectName: "search"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal playSong(var song)

    property var searchResults: []
    property string searchText: ""
    property bool searching: false
    property var searchHistory: []

    // 页面加载时从本地存储读取搜索历史
    Component.onCompleted: {
        ApiClient.getSearchHistory(function(d) {
            if (d.code === 200 && d.history) {
                searchPage.searchHistory = d.history
                console.log("[search] 加载搜索历史:", d.history.length, "条")
            }
        }, null)
    }

    // 虚拟键盘（bili风格，调用系统YInputPage）
    VirtualKeyboardInput {
        id: searchKeyboard
        onAccepted: {
            var kw = content.trim()
            if (kw.length > 0) {
                searchInput.text = kw
                doSearch()
            }
        }
    }

    // 顶部搜索栏
    Rectangle {
        id: searchBar
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
                    onClicked: searchPage.backClicked()
                }
            }

            // 搜索输入框（点击触发系统键盘）
            Rectangle {
                width: parent.width - 70
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.bgInput
                radius: Theme.radiusRound
                border.color: inputMouse.pressed ? Theme.primary : "transparent"
                border.width: inputMouse.pressed ? 1 : 0

                Behavior on border.color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 6

                    // 搜索图标
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "🔍"
                        font.pixelSize: 9
                        opacity: 0.5
                    }

                    // 显示文本（假输入框）
                    Text {
                        id: displayText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 20
                        text: searchInput.text.length > 0 ? searchInput.text : "搜索歌曲、歌手、歌单"
                        color: searchInput.text.length > 0 ? Theme.textPrimary : Theme.textTertiary
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }
                }

                // 清除按钮
                Rectangle {
                    visible: searchInput.text.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: clearMouse.pressed ? Theme.withAlpha(Theme.textPrimary, 0.2) : Theme.withAlpha(Theme.textPrimary, 0.1)

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: Theme.textSecondary
                        font.pixelSize: 10
                        font.bold: true
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        onClicked: {
                            searchInput.text = ""
                            searchPage.searchResults = []
                        }
                    }
                }

                // 隐藏的 TextInput 仅用于存储文本
                TextInput {
                    id: searchInput
                    visible: false
                }

                // 点击触发键盘
                MouseArea {
                    id: inputMouse
                    anchors.fill: parent
                    onClicked: searchKeyboard.open(searchInput.text)
                }
            }

            // 搜索按钮
            Rectangle {
                width: 36
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                color: searchMouse.pressed ? Theme.primaryDark : Theme.primary
                radius: Theme.radiusRound

                scale: searchMouse.pressed ? 0.93 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                Text {
                    anchors.centerIn: parent
                    text: "搜索"
                    color: Theme.textOnPrimary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    font.bold: true
                }

                MouseArea {
                    id: searchMouse
                    anchors.fill: parent
                    onClicked: if (searchInput.text.length > 0) doSearch()
                }
            }
        }
    }

    // 搜索历史（空状态时显示）
    Column {
        id: historyColumn
        anchors.top: searchBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 10
        spacing: 8
        visible: !searchPage.searching && searchPage.searchResults.length === 0 && searchPage.searchHistory.length > 0

        // 历史标题 + 清除按钮
        Row {
            width: parent.width
            spacing: 4

            Text {
                text: "搜索历史"
                color: Theme.textTertiary
                font.pixelSize: Theme.fontTiny
                font.family: Theme.fontFamily
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Item { width: 1; height: 1 }

            Text {
                text: "清除"
                color: Theme.primary
                font.pixelSize: Theme.fontTiny
                font.family: Theme.fontFamily
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: {
                        ApiClient.clearSearchHistory(function(d) {
                            if (d.code === 200) searchPage.searchHistory = []
                        })
                    }
                }
            }
        }

        // 历史标签流
        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                model: searchPage.searchHistory

                Rectangle {
                    width: historyText.width + 16
                    height: 20
                    color: histMouse.pressed ? Theme.bgCardHover : Theme.bgCard
                    radius: 10
                    border.color: Theme.borderLight
                    border.width: 0.5

                    Text {
                        id: historyText
                        anchors.centerIn: parent
                        text: modelData
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.fontFamily
                        maximumLineCount: 1
                    }

                    MouseArea {
                        id: histMouse
                        anchors.fill: parent
                        onClicked: {
                            searchInput.text = modelData
                            doSearch()
                        }
                    }
                }
            }
        }
    }

    // 空状态提示
    Text {
        anchors.centerIn: parent
        text: searchPage.searching ? "搜索中..." : (searchPage.searchHistory.length > 0 ? "" : "输入关键词搜索")
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSmall
        font.family: Theme.fontFamily
        visible: !searchPage.searching && searchPage.searchResults.length === 0 && searchPage.searchHistory.length === 0 || searchPage.searching
    }

    // 搜索结果列表
    ListView {
        id: resultList
        anchors.top: searchBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        visible: searchPage.searchResults.length > 0
        model: searchPage.searchResults
        cacheBuffer: 200

        delegate: Rectangle {
            width: parent.width
            height: 32
            color: index % 2 === 0 ? Theme.bgPrimary : Theme.bgCard

            scale: itemMouse.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: 60 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: index + 1
                    color: index < 3 ? Theme.primary : Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                    font.bold: index < 3
                    width: 14
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 50
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
                        text: modelData.artist
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    color: playMouse.pressed ? Theme.primaryDark : Theme.primary
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        color: "white"
                        font.pixelSize: 7
                    }

                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        onClicked: searchPage.playSong(modelData)
                    }
                }
            }

            MouseArea {
                id: itemMouse
                anchors.fill: parent
                onClicked: searchPage.playSong(modelData)
            }
        }
    }

    function addHistory(kw) {
        if (!kw) return
        // 保存到本地持久化存储
        ApiClient.addSearchHistory(kw, function(d) {
            if (d.code === 200 && d.history) {
                searchPage.searchHistory = d.history
            }
        }, null)
    }
    function doSearch() {
        var kw = searchInput.text.trim()
        if (!kw) return
        searchPage.searchText = kw
        addHistory(kw)
        searchPage.searching = true
        searchPage.searchResults = []
        ApiClient.search(kw, function(d) {
            searchPage.searching = false
            if (d.code === 200 && d.result && d.result.songs) {
                var list = []
                for (var i = 0; i < Math.min(d.result.songs.length, 30); i++) {
                    var s = d.result.songs[i]
                    var artists = []
                    if (s.ar) for (var j = 0; j < s.ar.length; j++) artists.push(s.ar[j].name)
                    list.push({
                        id: s.id,
                        name: s.name,
                        artist: artists.join(" / "),
                        album: s.al ? s.al.name : "",
                        duration: s.dt || 0
                    })
                }
                searchPage.searchResults = list
            }
        }, function(e) {
            searchPage.searching = false
            console.log("[search] 搜索失败:", e)
        })
    }
}
