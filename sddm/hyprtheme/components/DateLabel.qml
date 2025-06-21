import QtQuick 2.15

Text {
    font.family: "Go Mono"
    font.pointSize: 19
    color: "#0a0a0aBF"
    text: Qt.formatDateTime(new Date(), "dddd, MMMM d")

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: parent.text = Qt.formatDateTime(new Date(), "dddd, MMMM d")
    }
}
