// Magic Hat — KDE Plasma Login Splash Screen
// Shown between SDDM login and the desktop loading.
//
// Copyright (c) 2026 George Scott Foley — MIT License

import QtQuick 2.15

Rectangle {
    id: root
    color: "#0d0f1a"

    // ── loadingText: Plasma sets this to the stage label ─────────────────────
    property string loadingText: ""
    // ── stage: 0-6, incremented by KSplash ───────────────────────────────────
    property int stage: 0

    // ── Background gradient ───────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#0d0f1a" }
            GradientStop { position: 1.0; color: "#14161e" }
        }
    }

    // ── Subtle grid overlay ───────────────────────────────────────────────────
    Canvas {
        anchors.fill: parent
        opacity: 0.025
        onPaint: {
            var ctx = getContext("2d")
            ctx.strokeStyle = "#7c8cf8"
            ctx.lineWidth = 0.5
            for (var x = 0; x < width; x += 48) {
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
            }
            for (var y = 0; y < height; y += 48) {
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
            }
        }
    }

    // ── Central content ───────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 0

        // Hat emoji
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "🎩"
            font.pixelSize: 96

            // Gentle float animation
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { to: -8; duration: 1800; easing.type: Easing.InOutSine }
                NumberAnimation { to:  0; duration: 1800; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 24
            text: "Magic Hat"
            color: "#eaeaea"
            font.pixelSize: 36
            font.weight: Font.Light
            letterSpacing: 2

            // Fade in
            opacity: 0
            NumberAnimation on opacity { to: 1; duration: 600; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 8
            bottomPadding: 48
            text: "Familiar AI Desktop"
            color: "#7c8cf8"
            font.pixelSize: 14
            letterSpacing: 3
            opacity: 0
            NumberAnimation on opacity { to: 0.8; duration: 800; delay: 200; easing.type: Easing.OutCubic }
        }

        // ── Progress dots ─────────────────────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Repeater {
                model: 6
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: index < root.stage ? "#7c8cf8" : "#2e3050"
                    Behavior on color { ColorAnimation { duration: 300 } }

                    // Pulse on active step
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: index === root.stage - 1
                        NumberAnimation { to: 1.4; duration: 300; easing.type: Easing.OutCubic }
                        NumberAnimation { to: 1.0; duration: 300; easing.type: Easing.InCubic }
                        PauseAnimation { duration: 400 }
                    }
                }
            }
        }

        // ── Stage label ───────────────────────────────────────────────────────
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 16
            text: root.loadingText || stageName(root.stage)
            color: "#4b5563"
            font.pixelSize: 11
            Behavior on text { }  // no animation needed, just update
        }
    }

    // ── Stage name helper ─────────────────────────────────────────────────────
    function stageName(s) {
        var names = [
            "",
            "Starting session…",
            "Loading services…",
            "Starting compositor…",
            "Loading desktop…",
            "Starting Familiar…",
            "Ready"
        ]
        return names[Math.min(s, names.length - 1)] || ""
    }
}
