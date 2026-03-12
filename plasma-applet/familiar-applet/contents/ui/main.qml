// Familiar AI — System Tray Applet
// KDE Plasma 6 plasmoid — tray icon + chat overlay
//
// Copyright (c) 2026 George Scott Foley — MIT License

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents

PlasmoidItem {
    id: root

    // ── Configuration ────────────────────────────────────────────────────────
    readonly property string dashboardUrl: plasmoid.configuration.dashboardUrl || "http://localhost:5000"
    readonly property int pollIntervalSeconds: plasmoid.configuration.pollIntervalSeconds || 30

    // ── State ─────────────────────────────────────────────────────────────────
    property bool overlayOpen: false
    property int unreadCount: 0
    property string statusText: ""
    property bool agentOnline: false

    // ── Compact representation (tray icon) ────────────────────────────────────
    compactRepresentation: Item {
        id: trayIcon
        Layout.minimumWidth: Layout.minimumHeight
        Layout.minimumHeight: PlasmaCore.Units.iconSizes.medium

        PlasmaCore.IconItem {
            id: icon
            anchors.centerIn: parent
            width: PlasmaCore.Units.iconSizes.medium
            height: PlasmaCore.Units.iconSizes.medium
            source: root.agentOnline ? "familiar" : "familiar-offline"
            active: trayMouse.containsMouse
            opacity: root.agentOnline ? 1.0 : 0.5
        }

        // Unread badge
        Rectangle {
            visible: root.unreadCount > 0
            anchors { top: icon.top; right: icon.right; topMargin: -2; rightMargin: -2 }
            width: 14; height: 14
            radius: 7
            color: "#ef4444"
            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: root.unreadCount > 9 ? "9+" : root.unreadCount.toString()
                font.pixelSize: 8
                color: "white"
            }
        }

        MouseArea {
            id: trayMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.overlayOpen = !root.overlayOpen
        }
    }

    // ── Full representation (chat overlay) ────────────────────────────────────
    fullRepresentation: Overlay {
        dashboardUrl: root.dashboardUrl
        onCloseRequested: root.overlayOpen = false
    }

    // ── Status polling ────────────────────────────────────────────────────────
    Timer {
        interval: root.pollIntervalSeconds * 1000
        running: true
        repeat: true
        onTriggered: root.pollStatus()
    }

    Component.onCompleted: root.pollStatus()

    function pollStatus() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", root.dashboardUrl + "/api/status")
        xhr.timeout = 5000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.agentOnline = (xhr.status === 200)
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        root.unreadCount = data.unread_messages || 0
                        root.statusText = data.agent_name || "Familiar"
                    } catch (e) {}
                }
            }
        }
        xhr.send()
    }
}
