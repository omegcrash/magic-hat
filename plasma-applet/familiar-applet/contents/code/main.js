// Familiar AI Plasmoid — Background polling + helper functions
// Runs in the plasmoid JS context; called by main.qml timer.
//
// Copyright (c) 2026 George Scott Foley — MIT License

/**
 * Poll /api/status and /api/server/status, update applet state.
 * Called by the 30-second timer in main.qml.
 *
 * @param {string}   dashboardUrl  - e.g. "http://localhost:5000"
 * @param {function} onResult      - callback({online, unread, agentName, services})
 */
function pollAll(dashboardUrl, onResult) {
    var result = {
        online: false,
        unread: 0,
        agentName: "Familiar",
        pihole: false,
        services: []
    };

    // First: check agent status
    var agentXhr = new XMLHttpRequest();
    agentXhr.open("GET", dashboardUrl + "/api/status");
    agentXhr.timeout = 5000;
    agentXhr.onreadystatechange = function() {
        if (agentXhr.readyState !== XMLHttpRequest.DONE) return;
        if (agentXhr.status === 200) {
            result.online = true;
            try {
                var data = JSON.parse(agentXhr.responseText);
                result.unread = data.unread_messages || 0;
                result.agentName = data.agent_name || "Familiar";
            } catch (e) {}
        }
        // Second: check server/service status
        pollServices(dashboardUrl, result, onResult);
    };
    agentXhr.send();
}

function pollServices(dashboardUrl, result, onResult) {
    var svcXhr = new XMLHttpRequest();
    svcXhr.open("GET", dashboardUrl + "/api/server/status");
    svcXhr.timeout = 5000;
    svcXhr.onreadystatechange = function() {
        if (svcXhr.readyState !== XMLHttpRequest.DONE) {
            onResult(result);
            return;
        }
        if (svcXhr.status === 200) {
            try {
                var data = JSON.parse(svcXhr.responseText);
                var services = data.services || {};
                result.services = Object.keys(services).map(function(key) {
                    return { key: key, status: services[key].status || "unknown",
                             displayName: services[key].display_name || key };
                });
                // Pi-hole online = Privacy Mode active
                result.pihole = services["pihole"] && services["pihole"].status === "running";
            } catch (e) {}
        }
        onResult(result);
    };
    svcXhr.send();
}

/**
 * Send a chat message, return promise-style via callback.
 *
 * @param {string}   dashboardUrl
 * @param {string}   message
 * @param {function} onReply   callback(replyText, error)
 */
function sendChat(dashboardUrl, message, onReply) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", dashboardUrl + "/api/chat");
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    xhr.timeout = 60000;
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
                onReply(data.response || data.message || "", null);
            } catch (e) {
                onReply("", "Parse error: " + e.message);
            }
        } else {
            onReply("", "HTTP " + xhr.status);
        }
    };
    xhr.send("message=" + encodeURIComponent(message));
}

/**
 * Load recent chat history.
 *
 * @param {string}   dashboardUrl
 * @param {int}      limit
 * @param {function} onMessages  callback(messages[])
 */
function loadHistory(dashboardUrl, limit, onMessages) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", dashboardUrl + "/api/chat/history?limit=" + (limit || 20));
    xhr.timeout = 8000;
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
                onMessages(data.messages || []);
            } catch (e) { onMessages([]); }
        } else {
            onMessages([]);
        }
    };
    xhr.send();
}
