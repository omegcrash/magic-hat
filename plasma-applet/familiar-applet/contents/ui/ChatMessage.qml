// Familiar AI — Chat Message Bubble
//
// Copyright (c) 2026 George Scott Foley — MIT License

import QtQuick 2.15
import QtQuick.Layouts 1.15

Item {
    id: bubble
    height: row.implicitHeight + 4

    property string role: "user"      // "user" | "assistant"
    property string body: ""
    property string timestamp: ""

    readonly property bool isUser: role === "user"

    RowLayout {
        id: row
        width: parent.width
        layoutDirection: isUser ? Qt.RightToLeft : Qt.LeftToRight
        spacing: 8

        // Avatar
        Rectangle {
            width: 28; height: 28; radius: 14
            color: isUser ? "#3d4070" : "#252745"
            border.color: isUser ? "#5a6adc" : "#7c8cf8"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: isUser ? "👤" : "🎩"
                font.pixelSize: 14
            }
        }

        // Bubble
        Rectangle {
            Layout.maximumWidth: bubble.width * 0.75
            color: isUser ? "#3d4070" : "#252745"
            border.color: isUser ? "#5a6adc" : "#3e4060"
            border.width: 1
            radius: 10
            implicitHeight: msgText.implicitHeight + 16
            implicitWidth: msgText.implicitWidth + 20

            Text {
                id: msgText
                anchors { fill: parent; margins: 8 }
                text: bubble.body
                color: "#eaeaea"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                lineHeight: 1.4
                textFormat: Text.PlainText
            }
        }
    }
}
