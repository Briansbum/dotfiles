import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: passwordBox
    width: 320
    height: 55

    property alias password: passwordField.text
    signal loginRequested(string password)

    Rectangle {
        anchors.fill: parent
        color: "#0a0a0aE6"
        radius: 8

        TextField {
            id: passwordField
            anchors.fill: parent
            echoMode: TextInput.Password
            placeholderText: "🔒  Enter Pass"
            font.family: "Go Mono"
            font.pixelSize: 16
            color: "#C8C8C8"
            background: null

            Keys.onReturnPressed: {
                passwordBox.loginRequested(passwordField.text)
            }
        }
    }
}
