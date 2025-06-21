import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: userBox
    width: 320
    height: 60

    property alias username: userSelector.currentText

    Rectangle {
        anchors.fill: parent
        color: "#0a0a0aE6"
        radius: 8

        ComboBox {
            id: userSelector
            anchors.fill: parent
            anchors.margins: 8
            model: sddm.users
            textRole: "name"

            font.family: "Go Mono"
            font.pointSize: 16
            background: null

            contentItem: Text {
                text: userSelector.displayText
                font.family: "Go Mono"
                font.pointSize: 16
                color: "#D8DEECAA"
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
            }
        }
    }
}
