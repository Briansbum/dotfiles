import QtQuick 2.15
import QtQuick.Controls 2.15
import "components" 1.0

Rectangle {
    width: 2560
    height: 1440
    color: "black"

    Image {
        anchors.fill: parent
        source: "omnium.png"
        fillMode: Image.PreserveAspectCrop
    }

    // Static welcome text
    Text {
        text: "Welcome!"
        x: 150; y: 320
        font.family: "Go Mono"
        font.pointSize: 55
        color: "#0a0a0aBF"
    }

    Clock { x: 240; y: 240 }
    DateLabel { x: 217; y: 175 }

    UserBox {
        id: userBox
        x: 160
        y: height - 140
    }

    PasswordBox {
        id: passwordBox
        x: 160
        y: height - 220
        onLoginRequested: {
            sddm.login(userBox.username, password, sddm.session)
        }
    }

    // Login status feedback
    Text {
        id: statusText
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 20
        color: "#D8DEECAA"
        font.family: "Go Mono"
        font.pointSize: 14
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            statusText.text = "Login failed";
        }
        function onLoginSucceeded() {
            statusText.text = "Welcome!";
        }
    }

    // Optional: song info placeholder
    Text {
        id: songInfo
        x: 50
        y: height - 50
        font.family: "Go Mono"
        font.pointSize: 14
        color: "#0a0a0aBF"
        text: "Playing..."

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: songInfo.text = "Static fallback"
        }
    }
}
