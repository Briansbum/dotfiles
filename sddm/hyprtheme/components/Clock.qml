import QtQuick 2.15

Text {
    font.family: "Go Mono"
    font.pointSize: 40
    color: "#0a0a0aBF"
    text: Qt.formatDateTime(new Date(), "hh:mm")
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: parent.text = Qt.formatDateTime(new Date(), "hh:mm")
    }
}
