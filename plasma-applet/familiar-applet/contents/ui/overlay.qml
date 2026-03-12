// Familiar AI — Chat Overlay Panel
// Opened when the tray icon is clicked.
//
// Copyright (c) 2026 George Scott Foley — MIT License

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.extras 2.0 as PlasmaExtras

Item {
    id: overlay
    width: 380
    height: 520

    signal closeRequested()

    property string dashboardUrl: "http://localhost:5000"
    property var messages: []
    property bool sending: false

    // ── Background ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#1e2030"
        radius: 10
        border.color: "#2e3050"
        border.width: 1
    }

    ColumnLayout {
        anchors { fill: parent; margins: 0 }
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 48
            color: "#252745"
            radius: 10
            // Flatten bottom radius
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 10; color: parent.color
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }

                Text {
                    text: "🎩"
                    font.pixelSize: 20
                }
                Text {
                    text: "Familiar"
                    color: "#eaeaea"
                    font.pixelSize: 15
                    font.weight: Font.SemiBold
                    Layout.fillWidth: true
                    leftPadding: 6
                }
                PlasmaComponents.ToolButton {
                    icon.name: "window-minimize"
                    flat: true
                    onClicked: overlay.closeRequested()
                    ToolTip.text: "Minimise"
                    ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    icon.name: "internet-web-browser"
                    flat: true
                    onClicked: Qt.openUrlExternally(overlay.dashboardUrl)
                    ToolTip.text: "Open Dashboard"
                    ToolTip.visible: hovered
                }
            }
        }

        // ── Message list ──────────────────────────────────────────────────────
        ScrollView {
            id: msgScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width

            Column {
                id: msgColumn
                width: msgScroll.width
                padding: 12
                spacing: 8

                Repeater {
                    model: overlay.messages
                    delegate: ChatMessage {
                        width: msgColumn.width - 24
                        role: modelData.role
                        body: modelData.body
                        timestamp: modelData.timestamp || ""
                    }
                }

                // Typing indicator
                Rectangle {
                    visible: overlay.sending
                    width: 56; height: 28; radius: 14
                    color: "#252745"
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: 3
                            Rectangle {
                                width: 6; height: 6; radius: 3
                                color: "#7c8cf8"
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.2; duration: 400; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutSine }
                                    PauseAnimation { duration: index * 150 }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Input ─────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: "#252745"
            radius: 10
            // Flatten top radius
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 10; color: parent.color
            }

            RowLayout {
                anchors { fill: parent; margins: 8 }
                spacing: 6

                TextField {
                    id: chatInput
                    Layout.fillWidth: true
                    placeholderText: "Ask Familiar anything…"
                    color: "#eaeaea"
                    placeholderTextColor: "#6b7280"
                    background: Rectangle { color: "transparent" }
                    font.pixelSize: 13
                    enabled: !overlay.sending
                    Keys.onReturnPressed: sendMessage()
                }

                PlasmaComponents.Button {
                    text: "→"
                    flat: false
                    enabled: chatInput.text.trim().length > 0 && !overlay.sending
                    onClicked: sendMessage()
                }
            }
        }
    }

    // ── Message loading + sending ─────────────────────────────────────────────
    Component.onCompleted: loadHistory()

    function loadHistory() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", overlay.dashboardUrl + "/api/chat/history?limit=20")
        xhr.timeout = 5000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    overlay.messages = data.messages || []
                    Qt.callLater(function() { msgScroll.contentY = msgScroll.contentHeight })
                } catch (e) {}
            }
        }
        xhr.send()
    }

    function sendMessage() {
        var text = chatInput.text.trim()
        if (!text || overlay.sending) return
        chatInput.text = ""
        overlay.sending = true
        overlay.messages = overlay.messages.concat([{role: "user", body: text, timestamp: ""}])
        Qt.callLater(function() { msgScroll.contentY = msgScroll.contentHeight })

        var xhr = new XMLHttpRequest()
        xhr.open("POST", overlay.dashboardUrl + "/api/chat")
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.timeout = 60000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                overlay.sending = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        var reply = data.response || data.message || ""
                        overlay.messages = overlay.messages.concat([{role: "assistant", body: reply, timestamp: ""}])
                        Qt.callLater(function() { msgScroll.contentY = msgScroll.contentHeight })
                    } catch (e) {}
                }
            }
        }
        xhr.send("message=" + encodeURIComponent(text))
    }
}
