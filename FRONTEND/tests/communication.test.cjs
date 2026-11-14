const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const frontendDir = path.resolve(__dirname, "..");

// Load UI Model
const contextUi = { window: {} };
contextUi.window = contextUi;
vm.runInNewContext(fs.readFileSync(path.join(frontendDir, "ui-model.js"), "utf8"), contextUi);
const ui = contextUi.CampusShareUiModel;

// Load API
const apiCalls = [];
const contextApi = {
    window: {},
    localStorage: {
        getItem: () => "mock-token",
        setItem: () => {},
        removeItem: () => {}
    },
    fetch: async (url, options) => {
        apiCalls.push({ url, options });
        return {
            ok: true,
            status: 200,
            json: async () => ({ success: true })
        };
    }
};
contextApi.window = contextApi;
vm.runInNewContext(fs.readFileSync(path.join(frontendDir, "api.js"), "utf8"), contextApi);
const api = contextApi.CampusShareApi;
api.setAccessTokenProvider(async () => "mock-jwt-token");

test("ui.conversationRole correctly distinguishes borrower and owner roles", () => {
    const conv = {
        id: "c1",
        borrower_id: "user-borrower-1",
        owner_id: "user-owner-2"
    };
    assert.equal(ui.conversationRole(conv, "user-borrower-1"), "borrower");
    assert.equal(ui.conversationRole(conv, "user-owner-2"), "owner");
    assert.equal(ui.conversationRole(conv, "user-outsider-3"), null);
    assert.equal(ui.conversationRole(null, "user-borrower-1"), null);
});

test("ui.conversationPartnerName displays partner's name accurately", () => {
    const conv = {
        id: "c1",
        borrower_id: "user-b",
        borrower_name: "Bob Borrower",
        owner_id: "user-o",
        owner_name: "Alice Owner"
    };
    assert.equal(ui.conversationPartnerName(conv, "user-b"), "Alice Owner");
    assert.equal(ui.conversationPartnerName(conv, "user-o"), "Bob Borrower");
    assert.equal(ui.conversationPartnerName(conv, null), "Student");
});

test("ui.activeMeetingProposal filters the active pending proposal", () => {
    const proposals = [
        { id: "p1", status: "cancelled", meeting_date: "2026-11-15" },
        { id: "p2", status: "pending", meeting_date: "2026-11-18", location: "Library" },
        { id: "p3", status: "declined", meeting_date: "2026-11-16" }
    ];
    const active = ui.activeMeetingProposal(proposals);
    assert.ok(active);
    assert.equal(active.id, "p2");
    assert.equal(active.location, "Library");
    assert.equal(ui.activeMeetingProposal([]), null);
    assert.equal(ui.activeMeetingProposal(null), null);
});

test("ui.confirmedMeeting identifies accepted meeting", () => {
    const proposals = [
        { id: "p1", status: "superseded" },
        { id: "p2", status: "accepted", meeting_date: "2026-11-20", meeting_time: "14:30" }
    ];
    const confirmed = ui.confirmedMeeting(proposals);
    assert.ok(confirmed);
    assert.equal(confirmed.id, "p2");
    assert.equal(confirmed.status, "accepted");
});

test("ui.formatMeetingTimeIST formats 24h times to readable IST notation", () => {
    assert.equal(ui.formatMeetingTimeIST("14:30"), "2:30 PM IST");
    assert.equal(ui.formatMeetingTimeIST("09:15"), "9:15 AM IST");
    assert.equal(ui.formatMeetingTimeIST("00:00"), "12:00 AM IST");
    assert.equal(ui.formatMeetingTimeIST("12:00"), "12:00 PM IST");
    assert.equal(ui.formatMeetingTimeIST(""), "");
    assert.equal(ui.formatMeetingTimeIST(null), "");
});

test("ui.ownerRequestActions allows return on return_requested and approved states", () => {
    const options = { isOwner: true, statusActionsEnabled: true };
    assert.deepEqual(Array.from(ui.ownerRequestActions({ id: 1, status: "pending" }, options)), ["approve", "reject"]);
    assert.deepEqual(Array.from(ui.ownerRequestActions({ id: 2, status: "approved" }, options)), ["return"]);
    assert.deepEqual(Array.from(ui.ownerRequestActions({ id: 3, status: "return_requested" }, options)), ["return"]);
    assert.deepEqual(Array.from(ui.ownerRequestActions({ id: 4, status: "returned" }, options)), []);
    assert.deepEqual(Array.from(ui.ownerRequestActions({ id: 5, status: "approved" }, { isOwner: false, statusActionsEnabled: true })), []);
});

test("CampusShareApi communication endpoints format URLs and JSON payloads correctly", async () => {
    apiCalls.length = 0;

    await api.conversations();
    assert.equal(apiCalls[apiCalls.length - 1].url, "http://127.0.0.1:18080/api/conversations");

    await api.conversationMessages("conv-123");
    assert.equal(apiCalls[apiCalls.length - 1].url, "http://127.0.0.1:18080/api/conversations/conv-123/messages");

    await api.sendMessage("conv-123", "Hello there!", "custom-key-12345");
    const lastSend = apiCalls[apiCalls.length - 1];
    assert.equal(lastSend.url, "http://127.0.0.1:18080/api/conversations/conv-123/messages");
    const sendBody = JSON.parse(lastSend.options.body);
    assert.equal(sendBody.content, "Hello there!");
    assert.equal(sendBody.client_idempotency_key, "custom-key-12345");

    await api.conversationMeetings("conv-123");
    assert.equal(apiCalls[apiCalls.length - 1].url, "http://127.0.0.1:18080/api/conversations/conv-123/meetings");

    await api.proposeMeeting("conv-123", {
        meeting_type: "handover",
        meeting_date: "2026-11-22",
        meeting_time: "16:00",
        location: "Cafeteria Gate"
    });
    const lastProp = apiCalls[apiCalls.length - 1];
    assert.equal(lastProp.url, "http://127.0.0.1:18080/api/conversations/conv-123/meetings");
    const propBody = JSON.parse(lastProp.options.body);
    assert.equal(propBody.location, "Cafeteria Gate");
    assert.equal(propBody.meeting_time, "16:00");

    await api.respondToMeeting("prop-456", "accept");
    const lastResp = apiCalls[apiCalls.length - 1];
    assert.equal(lastResp.url, "http://127.0.0.1:18080/api/meetings/prop-456/respond");
    assert.equal(JSON.parse(lastResp.options.body).action, "accept");

    await api.notifications();
    assert.equal(apiCalls[apiCalls.length - 1].url, "http://127.0.0.1:18080/api/notifications");

    await api.markNotificationsRead({ mark_all: true });
    const lastMark = apiCalls[apiCalls.length - 1];
    assert.equal(lastMark.url, "http://127.0.0.1:18080/api/notifications/mark-read");
    assert.equal(JSON.parse(lastMark.options.body).mark_all, true);

    await api.requestReturn("conv-123");
    const lastReturn = apiCalls[apiCalls.length - 1];
    assert.equal(lastReturn.url, "http://127.0.0.1:18080/api/conversations/conv-123/return-request");
});

test("index.html contains contact and handover details elements and removes standalone messages", () => {
    const html = fs.readFileSync(path.join(frontendDir, "index.html"), "utf8");
    const requiredIds = [
        "handoverDetailsPanel",
        "handoverDetailsText",
        "pickupLocation",
        "meetingPoint",
        "preferredPickupTime",
        "handoverInstructions"
    ];
    for (const id of requiredIds) {
        assert.ok(html.includes(`id="${id}"`), `Expected element id "${id}" to exist in index.html`);
    }
    assert.equal(html.includes('id="messagesNav"'), false, "messagesNav should be removed");
    assert.equal(html.includes('id="messagesSection"'), false, "messagesSection should be removed");
});

test("style.css contains responsive styles for communication layout and chat bubbles", () => {
    const css = fs.readFileSync(path.join(frontendDir, "style.css"), "utf8");
    assert.ok(css.includes(".communication-layout"), "Missing .communication-layout in style.css");
    assert.ok(css.includes(".conversations-sidebar"), "Missing .conversations-sidebar in style.css");
    assert.ok(css.includes(".conversation-thread-view"), "Missing .conversation-thread-view in style.css");
    assert.ok(css.includes(".message-bubble.mine"), "Missing .message-bubble.mine in style.css");
    assert.ok(css.includes(".message-bubble.theirs"), "Missing .message-bubble.theirs in style.css");
    assert.ok(css.includes(".meeting-card"), "Missing .meeting-card in style.css");
});

test("communication validation: empty message and invalid parameters are rejected", async () => {
    await assert.rejects(
        async () => { await api.sendMessage("c1", "   "); },
        /Message content cannot be empty/
    );
    await assert.rejects(
        async () => { await api.sendMessage("", "Valid message"); },
        /conversation ID is required/
    );
});

test("meeting proposal validation: requires valid type, date, time and location", async () => {
    await assert.rejects(
        async () => {
            await api.proposeMeeting("c1", {
                meeting_type: "invalid_type",
                meeting_date: "2026-11-20",
                meeting_time: "10:00",
                location: "Gate 1"
            });
        },
        /meeting_type must be/
    );
    await assert.rejects(
        async () => {
            await api.proposeMeeting("c1", {
                meeting_type: "handover",
                meeting_date: "",
                meeting_time: "10:00",
                location: "Gate 1"
            });
        },
        /meeting_date is required/
    );
    await assert.rejects(
        async () => {
            await api.proposeMeeting("c1", {
                meeting_type: "handover",
                meeting_date: "2026-11-20",
                meeting_time: "",
                location: "Gate 1"
            });
        },
        /meeting_time is required/
    );
    await assert.rejects(
        async () => {
            await api.proposeMeeting("c1", {
                meeting_type: "handover",
                meeting_date: "2026-11-20",
                meeting_time: "10:00",
                location: "   "
            });
        },
        /location is required/
    );
});

test("meeting response validation: requires valid action", async () => {
    await assert.rejects(
        async () => { await api.respondToMeeting("prop-1", "invalid_action"); },
        /action must be accept, decline, or cancel/
    );
});
