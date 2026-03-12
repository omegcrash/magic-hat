// Familiar AI — System Tray Applet
// KDE Plasma 6 plasmoid — tray icon + chat overlay
//
// Copyright (c) 2026 George Scott Foley — MIT License

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import "code/main.js" as FamiliarJS

PlasmoidItem {
    id: root

    // ── Configuration ────────────────────────────────────────────────────────
    readonly property string dashboardUrl: plasmoid.configuration.dashboardUrl || "http://localhost:5000"
    readonly property int pollIntervalSeconds: plasmoid.configuration.pollIntervalSeconds || 30

    // ── State ─────────────────────────────────────────────────────────────────
    property bool overlayOpen: false
    property int unreadCount: 0
    property string agentName: "Familiar"
    property bool agentOnline: false
    property bool pihole: false
    property var services: []

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
            source: "familiar"
            active: trayMouse.containsMouse
            opacity: root.agentOnline ? 1.0 : 0.5
        }

        // Unread message badge
        Rectangle {
            visible: root.unreadCount > 0
            anchors { top: icon.top; right: icon.right; topMargin: -2; rightMargin: -2 }
            width: 14; height: 14; radius: 7
            color: "#ef4444"
            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: root.unreadCount > 9 ? "9+" : root.unreadCount.toString()
                font.pixelSize: 8
                color: "white"
            }
        }

        // Privacy Mode indicator dot
        Rectangle {
            visible: root.pihole
            anchors { bottom: icon.bottom; right: icon.right; bottomMargin: -1; rightMargin: -1 }
            width: 8; height: 8; radius: 4
            color: "#22c55e"
            border.color: "#1e2030"
            border.width: 1
        }

        MouseArea {
            id: trayMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                if (mouse.button === Qt.LeftButton)
                    root.overlayOpen = !root.overlayOpen
            }
            ToolTip.visible: containsMouse
            ToolTip.text: root.agentOnline
                ? (root.pihole ? root.agentName + " · Privacy On" : root.agentName)
                : "Familiar — not connected"
        }
    }

    // ── Full representation (chat + services overlay) ─────────────────────────
    fullRepresentation: Overlay {
        dashboardUrl: root.dashboardUrl
        pihole: root.pihole
        services: root.services
        onCloseRequested: root.overlayOpen = false
    }

    // ── Status polling ────────────────────────────────────────────────────────
    Timer {
        interval: root.pollIntervalSeconds * 1000
        running: true
        repeat: true
        onTriggered: pollStatus()
    }

    Component.onCompleted: pollStatus()

    function pollStatus() {
        FamiliarJS.pollAll(root.dashboardUrl, function(result) {
            root.agentOnline = result.online
            root.unreadCount = result.unread
            root.agentName   = result.agentName
            root.pihole      = result.pihole
            root.services    = result.services
        })
    }
}
