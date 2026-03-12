// Magic Hat — SDDM Login Screen
// KDE Plasma display manager theme
// Copyright (c) 2026 George Scott Foley — MIT License

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920; height: 1080
    color: "#14161e"

    // ── Background ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#0d0f1a" }
            GradientStop { position: 1.0; color: "#1a1c2a" }
        }
    }

    // Subtle grid pattern overlay
    Canvas {
        anchors.fill: parent
        opacity: 0.03
        onPaint: {
            var ctx = getContext("2d")
            ctx.strokeStyle = "#7c8cf8"
            ctx.lineWidth = 0.5
            for (var x = 0; x < width; x += 40) {
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
            }
            for (var y = 0; y < height; y += 40) {
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
            }
        }
    }

    // ── Centre card ────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 400
        height: 460
        radius: 16
        color: "#1e2030"
        border.color: "#2e3050"
        border.width: 1

        // Drop shadow
        layer.enabled: true
        layer.effect: null  // simplified — full shadow needs Qt.labs.graphics

        ColumnLayout {
            anchors {
                fill: parent
                margins: 40
            }
            spacing: 0

            // ── Logo + title ──────────────────────────────────────────────
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "🎩"
                font.pixelSize: 56
                font.family: "Noto Emoji"
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                text: "Magic Hat"
                font.pixelSize: 24
                font.weight: Font.SemiBold
                color: "#eaeaea"
                font.family: "Noto Sans"
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                Layout.bottomMargin: 32
                text: "Familiar AI Desktop"
                font.pixelSize: 12
                color: "#6b7280"
                font.family: "Noto Sans"
            }

            // ── Username ──────────────────────────────────────────────────
            Text {
                text: "Username"
                font.pixelSize: 11
                color: "#9ca3af"
                font.family: "Noto Sans"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.bottomMargin: 16
                height: 40
                radius: 8
                color: "#252740"
                border.color: userInput.activeFocus ? "#7c8cf8" : "#3e4060"
                border.width: userInput.activeFocus ? 2 : 1

                TextInput {
                    id: userInput
                    anchors {
                        fill: parent
                        leftMargin: 12; rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    text: userModel.lastUser || ""
                    color: "#eaeaea"
                    selectionColor: "#7c8cf8"
                    font.pixelSize: 13
                    font.family: "Noto Sans"
                    KeyNavigation.tab: passwordInput
                    Keys.onReturnPressed: passwordInput.forceActiveFocus()
                }
            }

            // ── Password ──────────────────────────────────────────────────
            Text {
                text: "Password"
                font.pixelSize: 11
                color: "#9ca3af"
                font.family: "Noto Sans"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.bottomMargin: 24
                height: 40
                radius: 8
                color: "#252740"
                border.color: passwordInput.activeFocus ? "#7c8cf8" : "#3e4060"
                border.width: passwordInput.activeFocus ? 2 : 1

                TextInput {
                    id: passwordInput
                    anchors {
                        fill: parent
                        leftMargin: 12; rightMargin: 12
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: TextInput.Password
                    color: "#eaeaea"
                    selectionColor: "#7c8cf8"
                    font.pixelSize: 13
                    font.family: "Noto Sans"
                    KeyNavigation.tab: loginButton
                    Keys.onReturnPressed: doLogin()
                }
            }

            // ── Login button ──────────────────────────────────────────────
            Rectangle {
                id: loginButton
                Layout.fillWidth: true
                height: 44
                radius: 8
                color: loginMouse.containsPress ? "#6c7ce8" : (loginMouse.containsMouse ? "#8b9cf8" : "#7c8cf8")

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "Sign In"
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.weight: Font.SemiBold
                    font.family: "Noto Sans"
                }

                MouseArea {
                    id: loginMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: doLogin()
                }
            }

            // ── Error message ─────────────────────────────────────────────
            Text {
                id: errorMsg
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                visible: text !== ""
                text: ""
                color: "#ef4444"
                font.pixelSize: 11
                font.family: "Noto Sans"
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Session / power bar ────────────────────────────────────────────────
    RowLayout {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 24
        }
        spacing: 16

        // Session selector
        ComboBox {
            id: sessionSelector
            model: sessionModel
            textRole: "name"
            implicitWidth: 160
            implicitHeight: 32
            font.pixelSize: 11
            font.family: "Noto Sans"
            background: Rectangle {
                radius: 6
                color: "#1e2030"
                border.color: "#3e4060"
            }
            contentItem: Text {
                text: sessionSelector.displayText
                color: "#9ca3af"
                font: sessionSelector.font
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8
            }
        }

        // Power buttons
        Repeater {
            model: [
                { icon: "⏸", label: "Suspend",  action: function() { sddm.suspend() } },
                { icon: "↺",  label: "Restart",  action: function() { sddm.reboot() } },
                { icon: "⏻",  label: "Shutdown", action: function() { sddm.powerOff() } }
            ]
            delegate: Rectangle {
                width: 72; height: 32; radius: 6
                color: paMouse.containsMouse ? "#2e3050" : "transparent"
                border.color: "#3e4060"; border.width: 1
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    anchors.centerIn: parent
                    text: modelData.icon + "  " + modelData.label
                    color: "#9ca3af"; font.pixelSize: 10; font.family: "Noto Sans"
                }
                MouseArea {
                    id: paMouse; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.action()
                }
            }
        }
    }

    // ── Clock ──────────────────────────────────────────────────────────────
    Column {
        anchors { top: parent.top; right: parent.right; margins: 32 }
        spacing: 4
        Text {
            anchors.right: parent.right
            text: Qt.formatTime(new Date(), "h:mm AP")
            color: "#eaeaea"; font.pixelSize: 36
            font.weight: Font.Light; font.family: "Noto Sans"
        }
        Text {
            anchors.right: parent.right
            text: Qt.formatDate(new Date(), "dddd, MMMM d")
            color: "#6b7280"; font.pixelSize: 13; font.family: "Noto Sans"
        }
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.update() }

    // ── Login logic ────────────────────────────────────────────────────────
    Connections {
        target: sddm
        function onLoginFailed() {
            errorMsg.text = "Incorrect username or password."
            passwordInput.text = ""
            passwordInput.forceActiveFocus()
        }
    }

    function doLogin() {
        errorMsg.text = ""
        sddm.login(userInput.text, passwordInput.text,
                   sessionSelector.currentIndex)
    }

    Component.onCompleted: {
        if (userInput.text !== "") {
            passwordInput.forceActiveFocus()
        } else {
            userInput.forceActiveFocus()
        }
    }
}
