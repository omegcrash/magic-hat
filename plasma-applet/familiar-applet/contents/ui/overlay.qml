// Familiar AI — Chat Overlay Panel
// Opened when the tray icon is clicked.
// Tabs: Chat | Services
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
    height: 540

    signal closeRequested()

    property string dashboardUrl: "http://localhost:5000"
    property var messages: []
    property bool sending: false
    property bool pihole: false
    property var services: []

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
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 10; color: parent.color
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }

                Text { text: "🎩"; font.pixelSize: 20 }

                Text {
                    text: "Familiar"
                    color: "#eaeaea"
                    font.pixelSize: 15
                    font.weight: Font.SemiBold
                    Layout.fillWidth: true
                    leftPadding: 6
                }

                // Privacy Mode badge — shown when Pi-hole is active
                Rectangle {
                    visible: overlay.pihole
                    width: privacyLabel.implicitWidth + 12
                    height: 20
                    radius: 10
                    color: "#1a4a1a"
                    border.color: "#4ade80"
                    border.width: 1
                    Text {
                        id: privacyLabel
                        anchors.centerIn: parent
                        text: "🔒 Privacy On"
                        color: "#4ade80"
                        font.pixelSize: 9
                        font.weight: Font.Medium
                    }
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

        // ── Tab bar ───────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 36
            color: "#1e2030"

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 0

                Repeater {
                    model: ["Chat", "Services"]
                    delegate: Rectangle {
                        height: 36
                        width: (overlay.width - 24) / 2
                        color: "transparent"

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width - 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 2
                            color: tabStack.currentIndex === index ? "#7c8cf8" : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: tabStack.currentIndex === index ? "#eaeaea" : "#6b7280"
                            font.pixelSize: 12
                            font.weight: tabStack.currentIndex === index ? Font.SemiBold : Font.Normal
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: tabStack.currentIndex = index
                        }
                    }
                }
            }
        }

        // ── Tab content ───────────────────────────────────────────────────────
        StackLayout {
            id: tabStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 0

            // ── Chat tab ──────────────────────────────────────────────────────
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

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
                                                PauseAnimation { duration: index * 180 }
                                                NumberAnimation { to: 0.2; duration: 350; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1.0; duration: 350; easing.type: Easing.InOutSine }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Chat input ────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 52
                        color: "#252745"
                        radius: 10
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
                                enabled: chatInput.text.trim().length > 0 && !overlay.sending
                                onClicked: sendMessage()
                            }
                        }
                    }
                }
            }

            // ── Services tab ──────────────────────────────────────────────────
            Item {
                ScrollView {
                    anchors.fill: parent
                    clip: true
                    contentWidth: width

                    Column {
                        width: parent.width
                        padding: 16
                        spacing: 8

                        // Pi-hole toggle card
                        Rectangle {
                            width: parent.width - 32
                            height: 60
                            radius: 8
                            color: overlay.pihole ? "#0f2a1a" : "#1e2030"
                            border.color: overlay.pihole ? "#22c55e" : "#3e4060"
                            border.width: 1

                            RowLayout {
                                anchors { fill: parent; margins: 12 }

                                Text { text: "🛡️"; font.pixelSize: 22 }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: "Pi-hole"
                                        color: "#eaeaea"
                                        font.pixelSize: 13
                                        font.weight: Font.SemiBold
                                    }
                                    Text {
                                        text: overlay.pihole ? "Ad blocking active" : "Not running"
                                        color: overlay.pihole ? "#4ade80" : "#6b7280"
                                        font.pixelSize: 11
                                    }
                                }

                                PlasmaComponents.Button {
                                    text: overlay.pihole ? "Admin" : "Start"
                                    flat: true
                                    font.pixelSize: 11
                                    onClicked: {
                                        if (overlay.pihole)
                                            Qt.openUrlExternally(overlay.dashboardUrl.replace(":5000", "") + "/pihole/")
                                        else
                                            Qt.openUrlExternally(overlay.dashboardUrl + "/#server")
                                    }
                                }
                            }
                        }

                        // Service cards (from /api/server/status)
                        Repeater {
                            model: overlay.services
                            delegate: Rectangle {
                                width: parent.width - 32
                                height: 52
                                radius: 8
                                color: "#1e2030"
                                border.color: modelData.status === "running" ? "#3e4060" : "#2e2030"
                                border.width: 1

                                RowLayout {
                                    anchors { fill: parent; margins: 12 }

                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        color: modelData.status === "running" ? "#22c55e" :
                                               modelData.status === "stopped" ? "#6b7280" : "#ef4444"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.displayName || modelData.key
                                        color: "#eaeaea"
                                        font.pixelSize: 12
                                        leftPadding: 4
                                    }

                                    Text {
                                        text: modelData.status
                                        color: modelData.status === "running" ? "#4ade80" :
                                               modelData.status === "stopped" ? "#6b7280" : "#f87171"
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }

                        // Open dashboard link
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: 8
                            text: "Manage all services →"
                            color: "#7c8cf8"
                            font.pixelSize: 11
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally(overlay.dashboardUrl + "/#server")
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Data loading ──────────────────────────────────────────────────────────
    Component.onCompleted: {
        loadHistory()
        refreshServices()
    }

    function loadHistory() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", overlay.dashboardUrl + "/api/chat/history?limit=20")
        xhr.timeout = 5000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    overlay.messages = JSON.parse(xhr.responseText).messages || []
                    Qt.callLater(function() { msgScroll.contentY = msgScroll.contentHeight })
                } catch (e) {}
            }
        }
        xhr.send()
    }

    function refreshServices() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", overlay.dashboardUrl + "/api/server/status")
        xhr.timeout = 5000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    var svcs = data.services || {}
                    overlay.pihole = svcs["pihole"] && svcs["pihole"].status === "running"
                    overlay.services = Object.keys(svcs).map(function(k) {
                        return { key: k, status: svcs[k].status || "unknown",
                                 displayName: svcs[k].display_name || k }
                    })
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
                        var reply = JSON.parse(xhr.responseText).response || ""
                        overlay.messages = overlay.messages.concat([{role: "assistant", body: reply, timestamp: ""}])
                        Qt.callLater(function() { msgScroll.contentY = msgScroll.contentHeight })
                    } catch (e) {}
                }
            }
        }
        xhr.send("message=" + encodeURIComponent(text))
    }
}
