const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const frontend = path.resolve(__dirname, "..");

class FakeElement {
    constructor(id = "") {
        this.id = id;
        this.children = [];
        this.listeners = {};
        this.dataset = {};
        this.attributes = {};
        this.hidden = false;
        this.disabled = false;
        this.isConnected = true;
        this.value = "";
        this.textContent = "";
        this.className = "";
        this.classNames = new Set();
        this.classList = {
            toggle: (name, force) => {
                const shouldAdd = force === undefined ? !this.classNames.has(name) : Boolean(force);
                if (shouldAdd) this.classNames.add(name);
                else this.classNames.delete(name);
                return shouldAdd;
            },
            add: (name) => this.classNames.add(name),
            remove: (name) => this.classNames.delete(name),
            contains: (name) => this.classNames.has(name)
        };
        this.elements = {};
    }
    addEventListener(type, callback) {
        (this.listeners[type] ||= []).push(callback);
    }
    dispatch(type, extra = {}) {
        const event = { preventDefault() {}, currentTarget: this, target: this, ...extra };
        return (this.listeners[type] || []).map((callback) => callback(event));
    }
    append(...items) { this.children.push(...items); }
    appendChild(item) {
        if (item.parentElement) item.parentElement.children = item.parentElement.children.filter((child) => child !== item);
        item.parentElement = this;
        this.children.push(item);
        return item;
    }
    replaceChildren(...items) { this.children = [...items]; }
    add(item) { this.children.push(item); }
    get options() { return this.children; }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return this.attributes[name] || null; }
    querySelector(selector) {
        if (selector === 'button[type="submit"]') return this.submitButton || null;
        if (selector === ".borrow-due-date") return this.children.find((child) => child.className === "borrow-due-date") || null;
        return null;
    }
    closest(selector) {
        let current = this;
        while (current) {
            if (selector === ".borrow-request-card" && current.className === "borrow-request-card") return current;
            current = current.parentElement;
        }
        return null;
    }
    reportValidity() { return true; }
    reset() {}
    showModal() { this.open = true; }
    close() { this.open = false; }
    scrollIntoView() {}
}

class FakeOption {
    constructor(text, value) { this.textContent = text; this.value = String(value); }
}

function collectText(node) {
    return [node.textContent || "", ...(node.children || []).map(collectText)].join(" ");
}

function findButton(root, label) {
    if (root.textContent === label && root.listeners.click) return root;
    for (const child of root.children || []) {
        const found = findButton(child, label);
        if (found) return found;
    }
    return null;
}

function findCardForTitle(root, title) {
    return (root.children || []).find((card) => collectText(card).includes(title)) || null;
}

function createHarness({ statusEnabled = false, borrowEnabled = false, marketplaceEnabled = false, resourceImagesEnabled = marketplaceEnabled, failCreate = false, failUpdate = false, failDelete = false, failBorrow = false, failDetails = false, failCategories = false, initialRequests, initialTransferRequests = [], session: sessionOption, deferResources = false, deferCategories = false, emptyCategories = false, initialHash = "#home" } = {}) {
    const html = fs.readFileSync(path.join(frontend, "index.html"), "utf8");
    const elements = new Map(Array.from(html.matchAll(/\bid="([^"]+)"/g), (m) => [m[1], new FakeElement(m[1])]));
    const get = (id) => {
        if (!elements.has(id)) throw new Error(`Missing test DOM id ${id}`);
        return elements.get(id);
    };
    get("categoryFilter").value = "all";
    get("resourceTypeFilter").value = "all";
    get("listingModeFilter").value = "all";
    get("availabilityFilter").value = "all";
    get("sortSelect").value = "newest";
    get("resourceAvailability").value = "available";
    get("loginForm").submitButton = new FakeElement("loginSubmit");
    get("registerForm").submitButton = new FakeElement("registerSubmit");
    get("resourceForm").submitButton = get("resourceSaveButton");
    get("loginForm").elements = { email: get("loginEmail"), password: get("loginPassword") };
    get("registerForm").elements = { email: get("registerEmail"), password: get("registerPassword"), full_name: get("registerFullName") };

    const state = {
        resources: [
            { id: 1, title: "Algorithms", description: "Study notes", category_id: 10, owner_id: "student-a", resource_type: "book", availability_status: "available", created_at: "2026-11-10T00:00:00Z" },
            { id: 2, title: "Physics review", description: "Exam guide", category_id: 20, owner_id: "student-b", resource_type: "notes", availability_status: "available", created_at: "2026-11-11T00:00:00Z" }
        ],
        requests: initialRequests || [
            { id: 20, resource_id: 1, borrower_id: "student-b", status: "pending", requested_at: "2026-11-11T00:00:00Z", due_at: null, returned_at: null },
            { id: 21, resource_id: 2, borrower_id: "student-a", status: "approved", requested_at: "2026-11-10T00:00:00Z", due_at: null, returned_at: null }
        ],
        calls: [],
        transferRequests: initialTransferRequests,
        reports: [],
        images: [],
        marketplaceEnabled,
        resourceImagesEnabled,
        statusEnabled,
        borrowEnabled,
        failCreate,
        failUpdate,
        failDelete,
        failBorrow,
        failDetails,
        failCategories,
        resolveResources: null,
        resolveCategories: null,
        authListener: null
    };
    if (marketplaceEnabled) {
        Object.assign(state.resources[0], {
            listing_mode: "borrow", borrow_price_kind: "free", borrow_price_amount: null,
            listing_state: "active", sale_original_price: null, sale_price: null
        });
        Object.assign(state.resources[1], {
            listing_mode: "sell", borrow_price_kind: "free", borrow_price_amount: null,
            sale_original_price: 100, sale_price: 75, item_condition: "good",
            purchase_year: 2022, listing_state: "active"
        });
    }
    const categories = emptyCategories ? [] : [
        { id: 10, name: "Study Materials", created_at: "2026-01-01T00:00:00Z" },
        { id: 20, name: "Books", created_at: "2026-01-01T00:00:00Z" },
        { id: 30, name: "Documents", created_at: "2026-01-01T00:00:00Z" },
        { id: 40, name: "Digital Resources", created_at: "2026-01-01T00:00:00Z" },
        { id: 50, name: "Tutoring & Peer Help", created_at: "2026-01-01T00:00:00Z" },
        { id: 60, name: "Study Groups & Projects", created_at: "2026-01-01T00:00:00Z" },
        { id: 70, name: "Equipment & Electronics", created_at: "2026-01-01T00:00:00Z" },
        { id: 80, name: "Stationery & Supplies", created_at: "2026-01-01T00:00:00Z" },
        { id: 90, name: "Opportunities", created_at: "2026-01-01T00:00:00Z" },
        { id: 100, name: "Campus Life & Events", created_at: "2026-01-01T00:00:00Z" },
        { id: 110, name: "Housing & Essentials", created_at: "2026-01-01T00:00:00Z" },
        { id: 120, name: "Announcements & Lost & Found", created_at: "2026-01-01T00:00:00Z" }
    ];
    const api = {
        setAccessTokenProvider() {},
        health: async () => ({ features: {
            borrow_request_rpc_enabled: state.borrowEnabled,
            borrow_status_rpc_enabled: state.statusEnabled,
            marketplace_enabled: state.marketplaceEnabled,
            resource_images_enabled: state.resourceImagesEnabled
        } }),
        getCategories: async () => {
            if (state.failCategories) throw new Error("Categories endpoint is unavailable.");
            if (deferCategories) return new Promise((resolve) => { state.resolveCategories = () => resolve(categories); });
            return categories;
        },
        getResources: async () => deferResources
            ? new Promise((resolve) => { state.resolveResources = () => resolve(state.resources); })
            : state.resources,
        resource: async (id) => {
            state.calls.push(["detail", id]);
            if (state.failDetails) throw new Error("Could not load resource details.");
            return state.resources.find((row) => String(row.id) === String(id));
        },
        borrowRequests: async () => state.requests,
        transferRequests: async () => state.transferRequests,
        myListingReports: async () => state.reports,
        reviewListingReport: async (id, outcome, notes) => { state.calls.push(["report-review", id, outcome, notes]); },
        resourceImages: async (resourceId) => state.images.filter((image) => String(image.resource_id) === String(resourceId)),
        addResourceImages: async (resourceId, images) => {
            state.calls.push(["image-metadata", resourceId, images]);
            state.images.push(...images.map((image, index) => ({ ...image, id: index + 1, resource_id: resourceId })));
            return state.images;
        },
        deleteResourceImage: async (id) => { state.calls.push(["image-delete", id]); state.images = state.images.filter((image) => image.id !== id); },
        reorderResourceImages: async (resourceId, ids) => {
            state.calls.push(["image-reorder", resourceId, ids]);
            const order = new Map(ids.map((id, index) => [String(id), index]));
            state.images.forEach((image) => {
                if (String(image.resource_id) === String(resourceId) && order.has(String(image.id))) image.sort_order = order.get(String(image.id));
            });
        },
        handoverDetails: async () => null,
        saveHandoverDetails: async (_id, details) => { state.calls.push(["handover", details]); },
        createTransferRequest: async (resourceId, requestType) => {
            state.calls.push(["transfer-request", resourceId, requestType]);
            const resource = state.resources.find((row) => String(row.id) === String(resourceId));
            const request = { id: 50, resource_id: resourceId, owner_id: resource.owner_id, requester_id: "student-a", request_type: requestType, status: "pending", requested_at: "2026-11-12T00:00:00Z" };
            state.transferRequests.push(request);
            return [request];
        },
        approveTransferRequest: async (id) => {
            state.calls.push(["transfer-approve", id]);
            state.transferRequests = state.transferRequests.map((row) => String(row.id) === String(id)
                ? { ...row, status: "approved" }
                : row);
        },
        rejectTransferRequest: async (id) => {
            state.calls.push(["transfer-reject", id]);
            state.transferRequests = state.transferRequests.map((row) => String(row.id) === String(id) ? { ...row, status: "rejected" } : row);
        },
        completeSale: async (id) => {
            state.calls.push(["sale-complete", id]);
            state.transferRequests = state.transferRequests.map((row) => String(row.id) === String(id) ? { ...row, status: "completed" } : row);
        },
        completeDonation: async (id) => {
            state.calls.push(["donation-complete", id]);
            state.transferRequests = state.transferRequests.map((row) => String(row.id) === String(id) ? { ...row, status: "completed" } : row);
        },
        reportListing: async (resourceId, report) => {
            state.calls.push(["report", resourceId, report]);
            state.reports.push({ ...report, resource_id: resourceId, status: "pending" });
        },
        createResource: async (payload) => {
            state.calls.push(["create", payload]);
            if (state.failCreate) throw new Error("Could not save resource.");
            const created = { ...payload, id: 3, owner_id: "student-a", created_at: "2026-11-12T00:00:00Z" };
            state.resources.push(created);
            return [created];
        },
        updateResource: async (id, payload) => {
            state.calls.push(["update", id, payload]);
            if (state.failUpdate) throw new Error("Could not update resource.");
            state.resources = state.resources.map((row) => String(row.id) === String(id) ? { ...row, ...payload } : row);
        },
        deleteResource: async (id) => {
            state.calls.push(["delete", id]);
            if (state.failDelete) throw new Error("Could not delete resource.");
            state.resources = state.resources.filter((row) => String(row.id) !== String(id));
        },
        createBorrowRequest: async (payload) => {
            state.calls.push(["borrow", payload]);
            if (state.failBorrow) throw new Error("Borrowing request could not be submitted.");
            state.requests.push({ id: 22, resource_id: payload.resource_id, borrower_id: "student-a", status: "pending", requested_at: "2026-11-12T00:00:00Z", due_at: null, returned_at: null });
        },
        approveBorrowRequest: async (id) => {
            state.calls.push(["approve", id]);
            state.requests = state.requests.map((row) => String(row.id) === String(id) ? { ...row, status: "approved" } : row);
        },
        rejectBorrowRequest: async (id) => {
            state.calls.push(["reject", id]);
            state.requests = state.requests.map((row) => String(row.id) === String(id) ? { ...row, status: "rejected" } : row);
        },
        returnBorrowedResource: async (id) => {
            state.calls.push(["return", id]);
            state.requests = state.requests.map((row) => String(row.id) === String(id) ? { ...row, status: "returned", returned_at: "2026-11-12T00:00:00Z" } : row);
        }
    };
    const defaultSession = { access_token: "mock-token", user: { id: "student-a", email: "student-a@example.test" } };
    const session = sessionOption === undefined ? defaultSession : sessionOption;
    const auth = {
        isConfigured: true,
        getSession: async () => ({ data: { session }, error: null }),
        onAuthStateChange(callback) { state.authListener = callback; },
        signOut: async () => ({ error: null }),
        uploadResourceImage: async (path, file) => { state.calls.push(["image-upload", path, file.name]); return { error: null }; },
        removeResourceImages: async (paths) => { state.calls.push(["image-remove", paths]); return { error: null }; },
        createResourceImageUrls: async (paths) => ({ data: paths.map((path) => ({ path, signedUrl: "https://signed.test/image" })), error: null })
    };
    const statGrid = new FakeElement("statGrid");
    const documentListeners = {};
    const document = {
        getElementById: get,
        querySelector: (selector) => selector === ".stat-grid" ? statGrid : null,
        createElement: (tag) => new FakeElement(tag),
        addEventListener(type, callback) { (documentListeners[type] ||= []).push(callback); },
        dispatchEvent(type, event = {}) {
            (documentListeners[type] || []).forEach((callback) => callback(event));
        }
    };
    const context = {
        document,
        Option: FakeOption,
        CampusShareApi: api,
        CampusShareAuth: auth,
        CampusShareUiModel: null,
        statGrid,
        confirm: () => true,
        setTimeout: (callback) => callback(),
        console
    };
    const windowListeners = {};
    const historyEntries = [initialHash];
    let historyIndex = 0;
    let currentHash = initialHash;
    context.addEventListener = (type, callback) => {
        (windowListeners[type] ||= []).push(callback);
    };
    context.dispatchWindowEvent = (type) => {
        (windowListeners[type] || []).forEach((callback) => callback());
    };
    context.location = {
        get hash() { return currentHash; },
        set hash(value) {
            if (value === currentHash) return;
            currentHash = value;
            historyEntries.splice(historyIndex + 1);
            historyEntries.push(value);
            historyIndex = historyEntries.length - 1;
            context.dispatchWindowEvent("hashchange");
        }
    };
    context.history = {
        back() {
            if (historyIndex <= 0) return;
            currentHash = historyEntries[--historyIndex];
            context.dispatchWindowEvent("popstate");
            context.dispatchWindowEvent("hashchange");
        },
        forward() {
            if (historyIndex >= historyEntries.length - 1) return;
            currentHash = historyEntries[++historyIndex];
            context.dispatchWindowEvent("popstate");
            context.dispatchWindowEvent("hashchange");
        }
    };
    context.window = context;
    vm.runInNewContext(fs.readFileSync(path.join(frontend, "ui-model.js"), "utf8"), context);
    vm.runInNewContext(fs.readFileSync(path.join(frontend, "app.js"), "utf8"), context);
    return { get, state, context, document };
}

async function settle() {
    for (let i = 0; i < 8; i++) await new Promise((resolve) => setImmediate(resolve));
}

test("signed-in dashboard loads real counts and separates borrower/owner requests", async () => {
    const harness = createHarness();
    await settle();
    harness.get("dashboardNav").dispatch("click");
    assert.equal(harness.get("dashboard").hidden, false);
    assert.equal(harness.get("statMyResources").textContent, "1");
    assert.equal(harness.get("statAvailableResources").textContent, "1");
    assert.equal(harness.get("statPendingRequests").textContent, "1");
    assert.equal(harness.get("statApprovedRequests").textContent, "1");
    assert.match(harness.get("welcomeSummary").textContent, /1 resource listed/);
    assert.match(harness.get("welcomeAvailableSummary").textContent, /1 of your resources/);
    assert.equal(harness.get("sidebarStudentEmail").textContent, "student-a@example.test");
    assert.match(collectText(harness.get("recentResources")), /Physics review/);
    assert.match(collectText(harness.get("myActivityList")), /Algorithms/);
    assert.match(collectText(harness.get("myActivityList")), /Physics review/);
    assert.match(collectText(harness.get("myBorrowRequests")), /Physics review/);
    assert.match(collectText(harness.get("ownerBorrowRequests")), /Algorithms/);
    assert.equal(findButton(harness.get("ownerBorrowRequests"), "Approve"), null);
});

test("signed-out state hides student tools; sign-in and sign-out update navigation and dashboard", async () => {
    const harness = createHarness({ session: null });
    await settle();
    assert.equal(harness.get("dashboard").hidden, true);
    assert.equal(harness.get("dashboardNav").hidden, true);
    assert.equal(harness.get("showAddForm").hidden, true);
    assert.match(harness.get("resourceCount").textContent, /Log in/);

    harness.state.authListener("SIGNED_IN", { access_token: "mock-token", user: { id: "student-a" } });
    await settle();
    assert.equal(harness.get("dashboard").hidden, true);
    harness.get("dashboardNav").dispatch("click");
    assert.equal(harness.get("dashboard").hidden, false);
    assert.equal(harness.get("dashboardNav").hidden, false);
    assert.equal(harness.get("showAddForm").hidden, false);

    await Promise.all(harness.get("authButton").dispatch("click"));
    assert.equal(harness.get("dashboard").hidden, true);
    assert.equal(harness.get("requestsNav").hidden, true);
});

test("registration rate limits show a friendly no-retry message and concurrent submits send only once", async () => {
    const harness = createHarness({ session: null });
    await settle();
    const submittedEmails = [];
    let releaseSignup;
    harness.context.CampusShareAuth.signUp = (email) => {
        submittedEmails.push(email);
        return new Promise((resolve) => { releaseSignup = resolve; });
    };
    const form = harness.get("registerForm");
    form.elements.full_name.value = "Campus Student";
    form.elements.email.value = "student@college.edu";
    form.elements.password.value = "example-password";
    form.dispatch("submit");
    form.elements.email.value = "student@gmail.com";
    form.dispatch("submit");
    assert.deepEqual(submittedEmails, ["student@college.edu"]);
    releaseSignup({ data: null, error: { status: 429, code: "over_email_send_rate_limit", message: "email rate limit exceeded" } });
    await settle();
    assert.match(harness.get("authMessage").textContent, /registration email limit reached/i);
    assert.match(harness.get("authMessage").textContent, /wait before trying again/i);
    assert.match(harness.get("authMessage").textContent, /college and personal email addresses are supported/i);
    assert.deepEqual(submittedEmails, ["student@college.edu"]);
});
test("signup forwards college and personal email addresses without a domain restriction", async () => {
    const harness = createHarness({ session: null });
    await settle();
    const submittedEmails = [];
    harness.context.CampusShareAuth.signUp = async (email) => {
        submittedEmails.push(email);
        return { data: { user: null, session: null }, error: null };
    };
    const form = harness.get("registerForm");
    form.elements.full_name.value = "Campus Student";
    form.elements.password.value = "example-password";
    for (const email of ["student@college.edu", "student@gmail.com"]) {
        form.elements.email.value = email;
        form.dispatch("submit");
        await settle();
    }
    assert.deepEqual(submittedEmails, ["student@college.edu", "student@gmail.com"]);
});
test("separate page navigation updates the URL and active item and supports back and forward", async () => {
    const harness = createHarness();
    await settle();
    const choosePage = (navId, route) => {
        if (harness.get("mobileNavToggle").getAttribute("aria-expanded") !== "true") {
            harness.get("mobileNavToggle").dispatch("click");
        }
        harness.get(navId).dispatch("click");
        assert.equal(harness.context.location.hash, "#" + route);
        assert.equal(harness.get(navId).getAttribute("aria-current"), "page");
        const pageTitles = {
            home: "Home",
            dashboard: "Dashboard",
            browse: "Browse Resources",
            sell: "Sell Resources",
            donate: "Donate Resources",
            "my-resources": "My Resources",
            borrowing: "Borrowing",
            about: "About"
        };
        assert.equal(harness.get("topbarPageTitle").textContent, pageTitles[route]);
        assert.equal(harness.get("mobileNavToggle").getAttribute("aria-expanded"), "false");
        assert.equal(harness.get("sidebarBackdrop").hidden, true);
    };

    choosePage("dashboardNav", "dashboard");
    assert.equal(harness.get("dashboard").hidden, false);
    assert.equal(harness.get("home").hidden, true);

    choosePage("browseNav", "browse");
    assert.equal(harness.get("browsePage").hidden, false);
    assert.equal(harness.get("dashboard").hidden, true);

    choosePage("sellNav", "sell");
    assert.equal(harness.get("sellPage").hidden, false);
    assert.equal(harness.get("browsePage").hidden, true);
    assert.equal(harness.get("sellMarketplaceNote").hidden, false, "the UI explains staging is not enabled");
    choosePage("donateNav", "donate");
    assert.equal(harness.get("donatePage").hidden, false);
    assert.equal(harness.get("donateMarketplaceNote").hidden, false, "the UI does not imply a live marketplace");

    choosePage("myResourcesNav", "my-resources");
    assert.equal(harness.get("browsePage").hidden, true);
    assert.equal(harness.get("myResourcesPage").hidden, false);
    assert.equal(harness.get("resourcesPageHeading").textContent, "My Resources");
    assert.equal(harness.get("myResourcesNav").getAttribute("aria-current"), "page");
    harness.context.history.back();
    assert.equal(harness.context.location.hash, "#donate");
    assert.equal(harness.get("resourcesPageHeading").textContent, "Free donations");
    harness.context.history.forward();
    assert.equal(harness.context.location.hash, "#my-resources");

    choosePage("requestsNav", "borrowing");
    assert.equal(harness.get("borrowRequestsSection").hidden, false);
    choosePage("aboutNav", "about");
    assert.equal(harness.get("about").hidden, false);
    choosePage("homeNav", "home");
    assert.equal(harness.get("home").hidden, false);
});

test("dedicated Sell and Donate pages filter real loaded listing modes and expose marketplace filters only when enabled", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    harness.state.resources[0].listing_mode = "donate";
    harness.state.resources[0].listing_state = "active";
    harness.state.resources[1].listing_mode = "sell";
    harness.state.resources[1].listing_state = "active";
    await settle();

    harness.get("sellNav").dispatch("click");
    assert.equal(harness.get("sellMarketplaceNote").hidden, true);
    assert.equal(harness.get("listingModeFilter").hidden, true);
    assert.equal(harness.get("priceMinFilter").hidden, false);
    assert.equal(harness.get("conditionFilter").hidden, false);
    assert.deepEqual(harness.get("resourceGrid").children.map((card) => collectText(card).includes("Physics review")), [true]);

    harness.get("donateNav").dispatch("click");
    assert.equal(harness.get("donateMarketplaceNote").hidden, true);
    assert.equal(harness.get("conditionFilter").hidden, true);
    assert.deepEqual(harness.get("resourceGrid").children.map((card) => collectText(card).includes("Algorithms")), [true]);

    const disabledEmpty = createHarness();
    disabledEmpty.state.resources = [];
    await settle();
    disabledEmpty.get("sellNav").dispatch("click");
    assert.equal(disabledEmpty.get("sellMarketplaceNote").hidden, false);
    assert.equal(disabledEmpty.get("showAddForm").hidden, true);
    assert.equal(disabledEmpty.get("emptyAddResource").hidden, true, "a disabled Sell page cannot accidentally open a Borrow form");
});

test("hamburger closes by toggle, outside click, and Escape", async () => {
    const harness = createHarness();
    await settle();
    const toggle = harness.get("mobileNavToggle");
    const sidebar = harness.get("appSidebar");
    const backdrop = harness.get("sidebarBackdrop");

    toggle.dispatch("click");
    assert.equal(toggle.getAttribute("aria-expanded"), "true");
    assert.equal(sidebar.classList.contains("is-open"), true);
    assert.equal(sidebar.inert, false);
    assert.equal(backdrop.hidden, false);
    toggle.dispatch("click");
    assert.equal(toggle.getAttribute("aria-expanded"), "false");
    assert.equal(sidebar.classList.contains("is-open"), false);

    toggle.dispatch("click");
    backdrop.dispatch("click");
    assert.equal(toggle.getAttribute("aria-expanded"), "false");
    assert.equal(backdrop.hidden, true);

    toggle.dispatch("click");
    harness.document.dispatchEvent("keydown", { key: "Escape" });
    assert.equal(toggle.getAttribute("aria-expanded"), "false");
    assert.equal(sidebar.inert, true);
});

test("dashboard displays only the signed-in Auth profile name and empty activity state", async () => {
    const harness = createHarness({
        initialRequests: [],
        session: {
            access_token: "mock-token",
            user: {
                id: "student-a",
                email: "anup@example.test",
                user_metadata: { full_name: "Anup Student" }
            }
        }
    });
    await settle();
    harness.get("dashboardNav").dispatch("click");
    assert.equal(harness.get("dashboardStudentName").textContent, "Anup Student");
    assert.equal(harness.get("sidebarStudentName").textContent, "Anup Student");
    assert.equal(harness.get("sidebarAvatar").textContent, "AS");
    assert.equal(harness.get("topbarStudentName").textContent, "Anup Student");
    assert.equal(harness.get("topbarStudentEmail").textContent, "anup@example.test");
    assert.equal(harness.get("myActivityList").children.length, 0);
    assert.equal(harness.get("myActivityEmpty").hidden, false);
    assert.match(harness.get("myActivityEmpty").textContent, /No borrowing activity/);
});

test("page route survives refresh and protected routes redirect signed-out visitors", async () => {
    const restored = createHarness({ initialHash: "#my-resources" });
    await settle();
    assert.equal(restored.get("browsePage").hidden, true);
    assert.equal(restored.get("myResourcesPage").hidden, false);
    assert.equal(restored.get("resourcesPageHeading").textContent, "My Resources");
    assert.equal(restored.get("myResourcesNav").getAttribute("aria-current"), "page");

    const signedOut = createHarness({ initialHash: "#dashboard", session: null });
    await settle();
    assert.equal(signedOut.context.location.hash, "#home");
    assert.equal(signedOut.get("dashboard").hidden, true);
    assert.equal(signedOut.get("home").hidden, false);
});

test("resource and dashboard loading states clear after records arrive", async () => {
    const harness = createHarness({ deferResources: true });
    await settle();
    harness.get("browseNav").dispatch("click");
    assert.equal(harness.get("resourceGrid").getAttribute("aria-busy"), "true");
    assert.equal(harness.context.statGrid.getAttribute("aria-busy"), "true");
    assert.match(harness.get("resourceCount").textContent, /Loading/);
    harness.state.resolveResources();
    await settle();
    assert.equal(harness.get("resourceGrid").getAttribute("aria-busy"), "false");
    assert.equal(harness.context.statGrid.getAttribute("aria-busy"), "false");
});

test("resource details loads the selected record through the authenticated API helper", async () => {
    const harness = createHarness();
    await settle();
    harness.get("browseNav").dispatch("click");
    await Promise.all(findButton(harness.get("resourceGrid"), "Details").dispatch("click"));
    assert.deepEqual(harness.state.calls.find((call) => call[0] === "detail"), ["detail", 2]);
    assert.equal(harness.get("resourceDetailsDialog").open, true);
    assert.equal(harness.get("resourceDetailsTitle").textContent, "Physics review");
    assert.match(harness.get("resourceDetailsDescription").textContent, /Exam guide/);
});

test("resource detail failures render an error and do not show stale owner actions", async () => {
    const harness = createHarness({ failDetails: true });
    await settle();
    harness.get("browseNav").dispatch("click");
    await Promise.all(findButton(harness.get("resourceGrid"), "Details").dispatch("click"));
    assert.match(harness.get("resourceDetailsDescription").textContent, /Could not load resource details/);
    assert.equal(harness.get("resourceDetailsActions").children.length, 0);
});

test("browse availability/category filters, my listings, and clear filters update the rendered cards", async () => {
    const harness = createHarness();
    await settle();
    harness.get("browseNav").dispatch("click");
    harness.get("availabilityFilter").value = "available";
    harness.get("availabilityFilter").dispatch("change");
    assert.equal(harness.get("resourceGrid").children.length, 2);
    harness.get("searchInput").value = "Physics";
    harness.get("searchInput").dispatch("input");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    harness.get("searchInput").value = "";
    harness.get("categoryFilter").value = "20";
    harness.get("categoryFilter").dispatch("change");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    harness.get("categoryFilter").value = "all";
    harness.get("resourceTypeFilter").value = "book";
    harness.get("resourceTypeFilter").dispatch("change");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    assert.match(collectText(harness.get("resourceGrid")), /Algorithms/);
    harness.get("resourceTypeFilter").value = "all";
    harness.get("categoryFilter").value = "all";
    harness.get("myResourcesNav").dispatch("click");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    assert.equal(harness.get("resourceViewTitle").textContent, "My resources");
    harness.get("clearFilters").dispatch("click");
    assert.equal(harness.get("availabilityFilter").value, "all");
    assert.equal(harness.get("resourceTypeFilter").value, "all");
    assert.equal(harness.get("listingModeFilter").value, "all");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    assert.equal(harness.get("resourcesPageHeading").textContent, "My Resources");
});

test("browse listing-type filter separates Borrow, Sell, and Donate from material type", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    await settle();
    harness.get("browseNav").dispatch("click");
    harness.get("listingModeFilter").value = "sell";
    harness.get("listingModeFilter").dispatch("change");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    assert.match(collectText(harness.get("resourceGrid")), /Physics review/);
    harness.get("listingModeFilter").value = "donate";
    harness.get("listingModeFilter").dispatch("change");
    assert.equal(harness.get("resourceGrid").children.length, 0);
    harness.get("listingModeFilter").value = "borrow";
    harness.get("listingModeFilter").dispatch("change");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    assert.match(collectText(harness.get("resourceGrid")), /Algorithms/);
});

test("resource form validates, creates, refreshes dashboard, and reports failures", async () => {
    const harness = createHarness();
    await settle();
    harness.get("browseNav").dispatch("click");
    harness.get("showAddForm").dispatch("click");
    harness.get("resourceTitle").value = "   ";
    harness.get("resourceDescription").value = "Notes";
    harness.get("resourceCategory").value = "10";
    harness.get("resourceType").value = "book";
    harness.get("resourceAvailability").value = "available";
    harness.get("resourceForm").dispatch("submit");
    await settle();
    assert.equal(harness.state.calls.length, 0);
    assert.match(harness.get("resourceFormStatus").textContent, /title/i);

    harness.get("resourceTitle").value = "New textbook";
    harness.get("resourceForm").dispatch("submit");
    await settle();
    assert.equal(harness.state.calls[0][0], "create");
    assert.deepEqual(JSON.parse(JSON.stringify(harness.state.calls[0][1])), {
        title: "New textbook",
        description: "Notes",
        category_id: "10",
        resource_type: "book",
        availability_status: "available"
    });
    assert.equal(harness.get("statMyResources").textContent, "2");
    assert.match(collectText(harness.get("resourceGrid")), /New textbook/);

    const failing = createHarness({ failCreate: true });
    await settle();
    failing.get("browseNav").dispatch("click");
    failing.get("showAddForm").dispatch("click");
    failing.get("resourceTitle").value = "Textbook";
    failing.get("resourceDescription").value = "Notes";
    failing.get("resourceCategory").value = "10";
    failing.get("resourceType").value = "book";
    failing.get("resourceAvailability").value = "available";
    failing.get("resourceForm").dispatch("submit");
    await settle();
    assert.match(failing.get("resourceStatus").textContent, /Could not save resource/);
    assert.match(failing.get("resourceFormStatus").textContent, /Could not save resource/);
});

test("marketplace resource form validates sell pricing, saves handover, and displays the direct-payment notice", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    await settle();
    harness.get("browseNav").dispatch("click");
    assert.match(collectText(findCardForTitle(harness.get("resourceGrid"), "Physics review")), /25% below original/);
    assert.match(collectText(findCardForTitle(harness.get("resourceGrid"), "Physics review")), /CampusShare does not process or verify it/);

    harness.get("showAddForm").dispatch("click");
    harness.get("resourceTitle").value = "Used calculator";
    harness.get("resourceDescription").value = "Scientific calculator";
    harness.get("resourceCategory").value = "20";
    harness.get("resourceType").value = "calculator";
    harness.get("resourceAvailability").value = "available";
    harness.get("listingMode").value = "sell";
    harness.get("saleOriginalPrice").value = "120";
    harness.get("salePrice").value = "80";
    harness.get("itemCondition").value = "good";
    harness.get("purchaseYear").value = "2022";
    harness.get("pickupLocation").value = "Main library entrance";
    harness.get("meetingPoint").value = "Student center lobby";
    harness.get("contactPhone").value = "+91 98765 43210";
    harness.get("resourceForm").dispatch("submit");
    await settle();
    const created = harness.state.calls.find((call) => call[0] === "create")[1];
    assert.equal(created.listing_mode, "sell");
    assert.equal(created.borrow_price_kind, "free");
    assert.equal(created.sale_original_price, 120);
    assert.equal(created.sale_price, 80);
    assert.equal(created.item_condition, "good");
    assert.equal(created.purchase_year, 2022);
    assert.equal(harness.state.calls.some((call) => call[0] === "handover" && call[1].pickup_location === "Main library entrance" && call[1].meeting_point === "Student center lobby" && call[1].instructions.includes("Phone: +91 98765 43210")), true);

    await harness.context.CampusShareApi.resource(2);
    harness.get("resourceDetailsDialog").showModal();
    harness.context.CampusShareAuth = { createResourceImageUrls: async () => ({ data: [], error: null }) };
    // Use the existing Details action so the app exercises its normal dialog renderer.
    const detailsButton = findButton(findCardForTitle(harness.get("resourceGrid"), "Physics review"), "Details");
    detailsButton.dispatch("click");
    await settle();
    assert.equal(harness.get("resourcePaymentDisclaimer").hidden, false);
});

test("resource images validate, preview, remove, upload to Storage, and save metadata", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    await settle();
    harness.get("browseNav").dispatch("click");
    harness.get("showAddForm").dispatch("click");
    const fileInput = harness.get("resourceImages");
    fileInput.files = [{ name: "bad.gif", type: "image/gif", size: 10 }];
    fileInput.dispatch("change");
    assert.match(harness.get("resourceFormStatus").textContent, /JPEG, PNG, or WebP/);
    fileInput.files = [{ name: "too-large.png", type: "image/png", size: 5 * 1024 * 1024 + 1 }];
    fileInput.dispatch("change");
    assert.match(harness.get("resourceFormStatus").textContent, /5 MiB/);

    const file = { name: "front.png", type: "image/png", size: 1024 };
    const secondFile = { name: "cover.webp", type: "image/webp", size: 2048 };
    fileInput.files = [file];
    fileInput.dispatch("change");
    assert.equal(harness.get("imagePreviewList").children.length, 1);
    findButton(harness.get("imagePreviewList"), "Remove").dispatch("click");
    assert.equal(harness.get("imagePreviewList").children.length, 0);
    fileInput.files = [file, secondFile];
    fileInput.dispatch("change");
    assert.equal(harness.get("imagePreviewList").children.length, 2);
    findButton(harness.get("imagePreviewList"), "Make primary").dispatch("click");
    assert.equal(harness.get("imagePreviewList").children[0].children.find((child) => child.id === "img").alt, "cover.webp");

    harness.get("resourceTitle").value = "Photo listing";
    harness.get("resourceDescription").value = "Listing with a photo";
    harness.get("resourceCategory").value = "10";
    harness.get("resourceType").value = "book";
    harness.get("resourceAvailability").value = "available";
    harness.get("pickupLocation").value = "Main library";
    harness.get("meetingPoint").value = "Student center";
    harness.get("contactPhone").value = "+91 98765 43210";
    harness.get("resourceForm").dispatch("submit");
    await settle();
    assert.equal(harness.state.calls.some((call) => call[0] === "image-upload" && call[2] === "front.png"), true, JSON.stringify(harness.state.calls));
    assert.equal(harness.state.calls.some((call) => call[0] === "image-upload" && call[2] === "cover.webp"), true);
    assert.equal(harness.state.calls.some((call) => call[0] === "image-metadata" && call[1] === 3), true);
    assert.equal(harness.state.images.length, 2);
    assert.equal(harness.state.images.find((image) => image.alt_text === "cover.webp").sort_order, 0);
    assert.equal(harness.state.images.find((image) => image.alt_text === "front.png").sort_order, 1);
});

test("saved image removal is coordinated by the authenticated backend", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    harness.state.images.push({
        id: 999, resource_id: 1, storage_path: "student-a/1/saved.jpg",
        alt_text: "Saved photo", sort_order: 0
    });
    await settle();
    harness.get("myResourcesNav").dispatch("click");
    findButton(findCardForTitle(harness.get("resourceGrid"), "Algorithms"), "Edit").dispatch("click");
    await settle();
    findButton(harness.get("existingImageList"), "Remove photo").dispatch("click");
    await settle();
    assert.deepEqual(harness.state.calls.find((call) => call[0] === "image-delete"), ["image-delete", 999]);
    assert.equal(harness.state.calls.some((call) => call[0] === "image-remove"), false);
    assert.equal(harness.state.images.length, 0);
});

test("reordering saved images persists the selected primary image order", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    harness.state.images.push(
        { id: 101, resource_id: 1, storage_path: "student-a/1/first.jpg", alt_text: "First", sort_order: 0 },
        { id: 102, resource_id: 1, storage_path: "student-a/1/second.jpg", alt_text: "Second", sort_order: 1 }
    );
    await settle();
    harness.get("myResourcesNav").dispatch("click");
    findButton(findCardForTitle(harness.get("resourceGrid"), "Algorithms"), "Edit").dispatch("click");
    await settle();
    findButton(harness.get("existingImageList"), "Move later").dispatch("click");
    await settle();
    assert.equal(JSON.stringify(harness.state.calls.find((call) => call[0] === "image-reorder")),
        JSON.stringify(["image-reorder", 1, ["102", "101"]]));
    assert.deepEqual(harness.state.images.map((image) => image.sort_order), [1, 0]);
    assert.deepEqual(harness.get("existingImageList").children.map((wrapper) => wrapper.dataset.imageId), ["102", "101"]);
});

test("saved image metadata restores the primary photo and gallery in Browse and Details", async () => {
    const harness = createHarness({
        marketplaceEnabled: true,
        initialTransferRequests: [{ id: 91, resource_id: 2, owner_id: "student-b", requester_id: "student-a", request_type: "sell", status: "pending", requested_at: "2026-11-12T00:00:00Z" }]
    });
    harness.state.images.push(
        { id: "photo-primary", resource_id: 2, storage_path: "student-b/2/cover.jpg", alt_text: "Cover", sort_order: 0 },
        { id: "photo-detail", resource_id: 2, storage_path: "student-b/2/detail.webp", alt_text: "Detail", sort_order: 1 }
    );
    await settle();
    harness.get("browseNav").dispatch("click");
    await settle();
    const card = findCardForTitle(harness.get("resourceGrid"), "Physics review");
    const cardGallery = card.children.find((child) => child.className === "resource-card-images");
    assert.equal(cardGallery.children.length, 2);
    assert.equal(cardGallery.children[0].attributes["data-primary-image"], "true");
    assert.equal(cardGallery.children[0].alt, "Cover");

    findButton(card, "Details").dispatch("click");
    await settle();
    const detailsGallery = harness.get("resourceDetailsImages");
    assert.equal(detailsGallery.children.length, 2);
    assert.equal(detailsGallery.children[0].attributes["data-primary-image"], "true");
    assert.equal(detailsGallery.children[0].alt, "Cover");

    const borrowCard = harness.get("myBorrowRequests").children.find((item) =>
        item.children.some((child) => child.textContent === "Physics review"));
    const saleCard = harness.get("myTransferRequests").children.find((item) =>
        item.children.some((child) => child.textContent === "Physics review"));
    assert.equal(borrowCard.children.find((child) => child.className === "resource-card-images request-card-images").children.length, 2);
    assert.equal(saleCard.children.find((child) => child.className === "resource-card-images request-card-images").children.length, 2);
});

test("failed Storage upload attempts are cleaned up using the same signed-in session", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    harness.context.CampusShareAuth.uploadResourceImage = async (path) => {
        harness.state.calls.push(["image-upload-failed", path]);
        return { error: new Error("mock upload denied") };
    };
    await settle();
    harness.get("browseNav").dispatch("click");
    harness.get("showAddForm").dispatch("click");
    harness.get("resourceTitle").value = "Upload cleanup test";
    harness.get("resourceDescription").value = "Storage failure cleanup";
    harness.get("resourceCategory").value = "10";
    harness.get("resourceType").value = "book";
    harness.get("resourceAvailability").value = "available";
    harness.get("pickupLocation").value = "Main library";
    harness.get("meetingPoint").value = "Student center";
    harness.get("contactPhone").value = "+91 98765 43210";
    harness.get("resourceImages").files = [{ name: "cleanup.png", type: "image/png", size: 100 }];
    harness.get("resourceImages").dispatch("change");
    harness.get("resourceForm").dispatch("submit");
    await settle();
    const attempted = harness.state.calls.find((call) => call[0] === "image-upload-failed");
    const cleanup = harness.state.calls.find((call) => call[0] === "image-remove");
    assert.ok(attempted);
    assert.equal(JSON.stringify(cleanup), JSON.stringify(["image-remove", [attempted[1]]]));
    assert.match(harness.get("resourceFormStatus").textContent, /mock upload denied/);
});

test("image picker and primary preview remain available in Add and Edit when marketplace fields are hidden", async () => {
    const harness = createHarness({ marketplaceEnabled: false });
    await settle();
    harness.get("browseNav").dispatch("click");
    harness.get("showAddForm").dispatch("click");
    assert.equal(harness.get("marketplaceFields").hidden, true);
    assert.equal(harness.get("resourceImageSection").hidden, false);
    assert.equal(harness.get("resourceImages").hidden, false);
    assert.equal(harness.get("imageUploadAvailabilityNote").hidden, false);

    harness.get("resourceTitle").value = "Photo preview only";
    harness.get("resourceDescription").value = "Selection remains available.";
    harness.get("resourceCategory").value = "10";
    harness.get("resourceType").value = "book";
    harness.get("resourceAvailability").value = "available";
    const input = harness.get("resourceImages");
    input.files = [
        { name: "page.jpg", type: "image/jpeg", size: 500 },
        { name: "cover.png", type: "image/png", size: 700 }
    ];
    input.dispatch("change");
    assert.equal(harness.get("imagePreviewList").children.length, 2);
    findButton(harness.get("imagePreviewList"), "Make primary").dispatch("click");
    assert.equal(harness.get("imagePreviewList").children[0].children.find((child) => child.id === "img").alt, "cover.png");
    harness.get("resourceForm").dispatch("submit");
    await settle();
    assert.match(harness.get("resourceFormStatus").textContent, /not enabled by the backend/);
    assert.equal(harness.state.calls.some((call) => call[0] === "create"), false);

    harness.get("cancelAddForm").dispatch("click");
    harness.get("myResourcesNav").dispatch("click");
    findButton(findCardForTitle(harness.get("resourceGrid"), "Algorithms"), "Edit").dispatch("click");
    assert.equal(harness.get("resourceImageSection").hidden, false);
    assert.equal(harness.get("resourceImages").hidden, false);
    input.files = [{ name: "replacement.webp", type: "image/webp", size: 600 }];
    input.dispatch("change");
    assert.equal(harness.get("imagePreviewList").children.length, 1);
    assert.match(collectText(harness.get("imagePreviewList")), /Primary image/);
});

test("image upload can be enabled independently while marketplace fields and workflows stay disabled", async () => {
    const harness = createHarness({ marketplaceEnabled: false, resourceImagesEnabled: true });
    await settle();
    harness.get("browseNav").dispatch("click");
    harness.get("showAddForm").dispatch("click");
    assert.equal(harness.get("marketplaceFields").hidden, true);
    assert.equal(harness.get("marketplaceTransferSection").hidden, true);
    assert.equal(harness.get("imageUploadAvailabilityNote").hidden, true);
    harness.get("resourceTitle").value = "Images only listing";
    harness.get("resourceDescription").value = "Image feature isolated from marketplace";
    harness.get("resourceCategory").value = "10";
    harness.get("resourceType").value = "book";
    harness.get("resourceAvailability").value = "available";
    harness.get("resourceImages").files = [{ name: "cover.webp", type: "image/webp", size: 900 }];
    harness.get("resourceImages").dispatch("change");
    harness.get("resourceForm").dispatch("submit");
    await settle();
    assert.equal(harness.state.calls.some((call) => call[0] === "image-upload" && call[2] === "cover.webp"), true);
    assert.equal(harness.state.calls.some((call) => call[0] === "image-metadata" && call[1] === 3), true);
    assert.equal(harness.state.calls.some((call) => call[0] === "handover"), false);
    assert.equal(harness.get("marketplaceFields").hidden, true);
});

test("sell requests can be submitted and then owner-approved and completed in the UI mock", async () => {
    const requester = createHarness({ marketplaceEnabled: true });
    await settle();
    requester.get("browseNav").dispatch("click");
    findButton(findCardForTitle(requester.get("resourceGrid"), "Physics review"), "Request to buy").dispatch("click");
    await settle();
    assert.equal(requester.state.calls.some((call) => call[0] === "transfer-request" && call[2] === "sell"), true);
    assert.equal(requester.state.transferRequests[0].status, "pending");

    const owner = createHarness({
        marketplaceEnabled: true,
        session: { access_token: "owner-token", user: { id: "student-b", email: "owner@example.test" } },
        initialTransferRequests: [{ id: 50, resource_id: 2, owner_id: "student-b", requester_id: "student-a", request_type: "sell", status: "pending", requested_at: "2026-11-12T00:00:00Z" }]
    });
    await settle();
    owner.get("requestsNav").dispatch("click");
    findButton(owner.get("ownerTransferRequests"), "Approve").dispatch("click");
    await settle();
    assert.equal(owner.state.calls.some((call) => call[0] === "transfer-approve"), true);
    assert.equal(owner.state.transferRequests[0].status, "approved");
    findButton(owner.get("ownerTransferRequests"), "Confirm sale completed").dispatch("click");
    await settle();
    assert.equal(owner.state.calls.some((call) => call[0] === "sale-complete"), true);
    assert.equal(owner.state.transferRequests[0].status, "completed");
});

test("donations require owner approval and a separate permanent handover confirmation", async () => {
    const requester = createHarness({ marketplaceEnabled: true });
    await settle();
    requester.state.resources[1].listing_mode = "donate";
    requester.get("browseNav").dispatch("click");
    requester.get("availabilityFilter").dispatch("change");
    findButton(findCardForTitle(requester.get("resourceGrid"), "Physics review"), "Request donation").dispatch("click");
    await settle();
    assert.equal(requester.state.transferRequests[0].request_type, "donate");

    const owner = createHarness({
        marketplaceEnabled: true,
        session: { access_token: "owner-token", user: { id: "student-b", email: "owner@example.test" } },
        initialTransferRequests: [{ id: 52, resource_id: 2, owner_id: "student-b", requester_id: "student-a", request_type: "donate", status: "pending", requested_at: "2026-11-12T00:00:00Z" }]
    });
    await settle();
    owner.get("requestsNav").dispatch("click");
    findButton(owner.get("ownerTransferRequests"), "Approve").dispatch("click");
    await settle();
    assert.equal(owner.state.transferRequests[0].status, "approved");
    findButton(owner.get("ownerTransferRequests"), "Confirm donation handover").dispatch("click");
    await settle();
    assert.equal(owner.state.transferRequests[0].status, "completed");
    assert.equal(owner.state.calls.some((call) => call[0] === "donation-complete"), true);
    assert.equal(findButton(owner.get("ownerTransferRequests"), "Confirm sale completed"), null);
});

test("listing reports are submitted for human review without automatic account action", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    await settle();
    harness.get("browseNav").dispatch("click");
    findButton(findCardForTitle(harness.get("resourceGrid"), "Physics review"), "Details").dispatch("click");
    await settle();
    findButton(harness.get("resourceDetailsActions"), "Report listing").dispatch("click");
    harness.get("listingReportReason").value = "unreasonable_selling_price";
    harness.get("listingReportDetails").value = "Please review the displayed price.";
    harness.get("listingReportForm").dispatch("submit");
    await settle();
    assert.equal(harness.state.calls.some((call) => call[0] === "report" && call[2].reason === "unreasonable_selling_price"), true);
    assert.match(harness.get("borrowStatus").textContent, /report submitted/i);
    assert.match(harness.get("listingReportStatus").textContent, /human review/i);
});

test("moderation controls display only for the trusted moderator claim and submit review outcomes", async () => {
    const ordinary = createHarness({ marketplaceEnabled: true });
    ordinary.state.reports.push({ id: 77, reason: "other", details: "Review", status: "pending" });
    await settle();
    ordinary.get("requestsNav").dispatch("click");
    assert.equal(findButton(ordinary.get("myListingReports"), "Resolve report"), null);

    const moderator = createHarness({
        marketplaceEnabled: true,
        session: { access_token: "moderator-token", user: { id: "moderator-1", app_metadata: { campusshare_role: "moderator" } } }
    });
    moderator.state.reports.push({ id: 78, reason: "other", details: "Review", status: "pending" });
    await settle();
    moderator.get("requestsNav").dispatch("click");
    findButton(moderator.get("myListingReports"), "Resolve report").dispatch("click");
    await settle();
    assert.equal(moderator.state.calls.some((call) => call[0] === "report-review" && call[1] === 78 && call[2] === "resolved"), true);
});

test("all Add Resource entry points open the form; cancel closes without submitting", async () => {
    const harness = createHarness();
    await settle();
    harness.get("dashboardNav").dispatch("click");

    harness.get("dashboardAddResource").dispatch("click");
    assert.equal(harness.context.location.hash, "#browse");
    assert.equal(harness.get("browsePage").hidden, false);
    assert.equal(harness.get("resourceForm").hidden, false);
    assert.equal(harness.get("resourceFormHeading").textContent, "Add a Resource");
    assert.ok(harness.get("resourceCategory").options.length > 1);
    harness.get("cancelAddForm").dispatch("click");
    assert.equal(harness.get("resourceForm").hidden, true);
    assert.equal(harness.state.calls.length, 0);

    harness.get("showAddForm").dispatch("click");
    assert.equal(harness.get("resourceForm").hidden, false);
    harness.get("cancelAddForm").dispatch("click");

    harness.state.resources = [];
    await settle();
    harness.get("emptyAddResource").dispatch("click");
    assert.equal(harness.get("resourceForm").hidden, false);
    harness.get("cancelAddForm").dispatch("click");
    assert.equal(harness.state.calls.length, 0);
});

test("Add Resource form opens when categories have not loaded and explains the blocker", async () => {
    const harness = createHarness({ emptyCategories: true });
    await settle();
    harness.get("dashboardNav").dispatch("click");
    harness.get("dashboardAddResource").dispatch("click");
    assert.equal(harness.get("resourceForm").hidden, false);
    assert.match(harness.get("resourceFormStatus").textContent, /No categories are available in staging/i);
    assert.equal(harness.get("resourceCategory").options[0].textContent, "No categories available");
    assert.equal(harness.get("resourceCategory").options.length, 1);
    harness.get("cancelAddForm").dispatch("click");
    assert.equal(harness.get("resourceForm").hidden, true);
    assert.equal(harness.state.calls.length, 0);
});

test("category loading, population, selection, empty and API error states are explicit", async () => {
    const loading = createHarness({ deferCategories: true });
    await settle();
    loading.get("dashboardNav").dispatch("click");
    loading.get("dashboardAddResource").dispatch("click");
    assert.equal(loading.get("resourceCategory").options[0].textContent, "Loading categories…");
    assert.match(loading.get("resourceFormStatus").textContent, /Categories are loading/);
    loading.state.resolveCategories();
    await settle();
    assert.equal(loading.get("resourceCategory").options[1].textContent, "Study Materials");
    assert.equal(loading.get("resourceCategory").options[1].value, "10");
    assert.equal(loading.get("resourceCategory").options[2].value, "20");

    const failed = createHarness({ failCategories: true });
    await settle();
    assert.equal(failed.get("resourceGrid").children.length, 2, "resource results remain usable when categories fail");
    failed.get("dashboardNav").dispatch("click");
    failed.get("dashboardAddResource").dispatch("click");
    assert.equal(failed.get("resourceCategory").options[0].textContent, "Categories could not be loaded");
    assert.match(failed.get("resourceFormStatus").textContent, /use Refresh to try again/i);
});

test("Add Resource dropdown displays all twelve approved categories returned by the API", async () => {
    const harness = createHarness();
    await settle();
    harness.get("dashboardNav").dispatch("click");
    harness.get("dashboardAddResource").dispatch("click");
    const names = harness.get("resourceCategory").options.slice(1).map((option) => option.textContent);
    assert.equal(names.length, 12);
    assert.deepEqual(names, [
        "Study Materials", "Books", "Documents", "Digital Resources",
        "Tutoring & Peer Help", "Study Groups & Projects", "Equipment & Electronics",
        "Stationery & Supplies", "Opportunities", "Campus Life & Events",
        "Housing & Essentials", "Announcements & Lost & Found"
    ]);
});

test("Add Resource rejects a category ID that is not in the loaded category list", async () => {
    const harness = createHarness();
    await settle();
    harness.get("browseNav").dispatch("click");
    harness.get("showAddForm").dispatch("click");
    harness.get("resourceTitle").value = "Valid title";
    harness.get("resourceDescription").value = "Valid description";
    harness.get("resourceCategory").value = "999";
    harness.get("resourceType").value = "book";
    harness.get("resourceAvailability").value = "available";
    harness.get("resourceForm").dispatch("submit");
    await settle();
    assert.equal(harness.state.calls.some((call) => call[0] === "create"), false);
    assert.match(harness.get("resourceFormStatus").textContent, /Choose a category from the available list/);
});

test("edit and delete actions call the authenticated API and refresh owned listings", async () => {
    const harness = createHarness();
    await settle();
    harness.get("browseNav").dispatch("click");
    const ownerCard = findCardForTitle(harness.get("resourceGrid"), "Algorithms");
    const edit = findButton(ownerCard, "Edit");
    assert.ok(edit);
    edit.dispatch("click");
    harness.get("resourceTitle").value = "Updated algorithms";
    harness.get("resourceDescription").value = "Revised notes";
    harness.get("resourceCategory").value = "10";
    harness.get("resourceType").value = "book";
    harness.get("resourceAvailability").value = "unavailable";
    harness.get("resourceForm").dispatch("submit");
    await settle();
    assert.equal(harness.state.calls[0][0], "update");
    assert.equal(harness.get("statAvailableResources").textContent, "0");
    const deleteButton = findButton(findCardForTitle(harness.get("resourceGrid"), "Updated algorithms"), "Delete");
    assert.ok(deleteButton);
    deleteButton.dispatch("click");
    await settle();
    assert.equal(harness.state.calls[1][0], "delete");
    assert.equal(harness.get("statMyResources").textContent, "0");
});

test("edit and delete failures surface safe user-facing messages without crashing", async () => {
    const editFailure = createHarness({ failUpdate: true });
    await settle();
    editFailure.get("browseNav").dispatch("click");
    findButton(findCardForTitle(editFailure.get("resourceGrid"), "Algorithms"), "Edit").dispatch("click");
    editFailure.get("resourceTitle").value = "Changed title";
    editFailure.get("resourceDescription").value = "Study notes";
    editFailure.get("resourceCategory").value = "10";
    editFailure.get("resourceType").value = "book";
    editFailure.get("resourceAvailability").value = "available";
    editFailure.get("resourceForm").dispatch("submit");
    await settle();
    assert.match(editFailure.get("resourceStatus").textContent, /Could not update resource/);

    const deleteFailure = createHarness({ failDelete: true });
    await settle();
    deleteFailure.get("browseNav").dispatch("click");
    findButton(findCardForTitle(deleteFailure.get("resourceGrid"), "Algorithms"), "Delete").dispatch("click");
    await settle();
    assert.match(deleteFailure.get("resourceStatus").textContent, /Could not delete resource/);
    assert.equal(deleteFailure.state.resources.length, 2);
});

test("borrow and owner status actions stay hidden when feature flags are off and appear only for an owner when enabled", async () => {
    const noPriorRequest = [{ id: 20, resource_id: 1, borrower_id: "student-b", status: "pending", requested_at: "2026-11-11T00:00:00Z", due_at: null, returned_at: null }];
    const disabled = createHarness({ statusEnabled: false, borrowEnabled: false, initialRequests: noPriorRequest });
    await settle();
    disabled.get("browseNav").dispatch("click");
    assert.equal(findButton(findCardForTitle(disabled.get("resourceGrid"), "Physics review"), "Request to borrow"), null);
    assert.equal(findButton(disabled.get("ownerBorrowRequests"), "Approve"), null);

    const enabled = createHarness({ statusEnabled: true, borrowEnabled: true, initialRequests: noPriorRequest });
    await settle();
    enabled.get("browseNav").dispatch("click");
    assert.ok(findButton(findCardForTitle(enabled.get("resourceGrid"), "Physics review"), "Request to borrow"));
    assert.ok(findButton(enabled.get("ownerBorrowRequests"), "Approve"));
    assert.ok(findButton(enabled.get("ownerBorrowRequests"), "Reject"));
    assert.equal(findButton(enabled.get("myBorrowRequests"), "Confirm return"), null);
});

test("borrow creation and owner status controls refresh lists after successful actions", async () => {
    const withoutOwnRequest = [{ id: 20, resource_id: 1, borrower_id: "student-b", status: "pending", requested_at: "2026-11-11T00:00:00Z", due_at: null, returned_at: null }];
    const harness = createHarness({ statusEnabled: true, borrowEnabled: true, initialRequests: withoutOwnRequest });
    await settle();
    harness.get("browseNav").dispatch("click");
    findButton(findCardForTitle(harness.get("resourceGrid"), "Physics review"), "Request to borrow").dispatch("click");
    await settle();
    assert.equal(harness.state.calls.some((call) => call[0] === "borrow"), true);
    assert.equal(harness.state.requests.at(-1).borrower_id, "student-a");
    assert.equal(harness.get("statPendingRequests").textContent, "2");

    findButton(harness.get("ownerBorrowRequests"), "Approve").dispatch("click");
    await settle();
    assert.equal(harness.state.calls.some((call) => call[0] === "approve"), true, harness.get("borrowStatus").textContent);
    assert.equal(harness.state.requests[0].status, "approved");
    assert.ok(findButton(harness.get("ownerBorrowRequests"), "Confirm return"));
    findButton(harness.get("ownerBorrowRequests"), "Confirm return").dispatch("click");
    await settle();
    assert.equal(harness.state.requests[0].status, "returned");
    assert.equal(harness.state.calls.some((call) => call[0] === "return"), true);
});

test("borrow request API failure is visible without fabricating a request", async () => {
    const noOwnRequest = [{ id: 20, resource_id: 1, borrower_id: "student-b", status: "pending", requested_at: "2026-11-11T00:00:00Z", due_at: null, returned_at: null }];
    const harness = createHarness({ borrowEnabled: true, failBorrow: true, initialRequests: noOwnRequest });
    await settle();
    harness.get("browseNav").dispatch("click");
    findButton(findCardForTitle(harness.get("resourceGrid"), "Physics review"), "Request to borrow").dispatch("click");
    await settle();
    assert.match(harness.get("resourceStatus").textContent, /could not be submitted/i);
    assert.equal(harness.state.requests.length, 1);
});

test("empty results and request failures render messages instead of stale empty stats", async () => {
    const empty = createHarness();
    empty.state.resources = [];
    empty.state.requests = [];
    await settle();
    assert.equal(empty.get("noResults").hidden, false);
    assert.equal(empty.get("statMyResources").textContent, "0");
    assert.equal(empty.get("myBorrowEmpty").hidden, false);

    const failed = createHarness();
    failed.context.CampusShareApi.borrowRequests = async () => { throw new Error("Request list unavailable"); };
    await settle();
    assert.equal(failed.get("statPendingRequests").textContent, "—");
    assert.equal(failed.get("myBorrowEmpty").hidden, true);
    assert.match(failed.get("borrowStatus").textContent, /Request list unavailable/);
});

test("My Resources tabs switch cleanly between My Borrow, My Sell, and My Donate", async () => {
    const harness = createHarness({ marketplaceEnabled: true });
    harness.state.resources.push(
        { id: 3, title: "Sell Keyboard", description: "Mechanical", category_id: 10, owner_id: "student-a", resource_type: "equipment", availability_status: "available", listing_mode: "sell", sale_price: 500, created_at: "2026-11-12T00:00:00Z" },
        { id: 4, title: "Donate Desk", description: "Study table", category_id: 10, owner_id: "student-a", resource_type: "furniture", availability_status: "available", listing_mode: "donate", created_at: "2026-11-12T00:00:00Z" }
    );
    await settle();
    harness.get("myResourcesNav").dispatch("click");
    await settle();

    // Default / My Borrow tab
    harness.get("myBorrowTab").dispatch("click");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    assert.match(collectText(harness.get("resourceGrid")), /Algorithms/);

    // Switch to My Sell tab
    harness.get("mySellTab").dispatch("click");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    assert.match(collectText(harness.get("resourceGrid")), /Sell Keyboard/);

    // Switch to My Donate tab
    harness.get("myDonateTab").dispatch("click");
    assert.equal(harness.get("resourceGrid").children.length, 1);
    assert.match(collectText(harness.get("resourceGrid")), /Donate Desk/);
});

test("owner-only delete permission: Account A can delete, Account B and C cannot see delete button and are rejected", async () => {
    // 1. Account A (owner: student-a)
    const harnessA = createHarness({ session: { access_token: "token-a", user: { id: "student-a", email: "student.a@vit.edu" } } });
    await settle();
    harnessA.get("myResourcesNav").dispatch("click");
    await settle();
    const cardA = findCardForTitle(harnessA.get("resourceGrid"), "Algorithms");
    const deleteBtnA = findButton(cardA, "Delete");
    assert.ok(deleteBtnA, "Owner Account A must see Delete button");

    // 2. Account B (student-b)
    const harnessB = createHarness({ session: { access_token: "token-b", user: { id: "student-b", email: "student.b@vit.edu" } } });
    await settle();
    harnessB.get("browseNav").dispatch("click");
    await settle();
    const cardB = findCardForTitle(harnessB.get("resourceGrid"), "Algorithms");
    assert.equal(findButton(cardB, "Delete"), null, "Non-owner Account B must not see Delete button");

    // 3. Account C (unrelated: student-c)
    const harnessC = createHarness({ session: { access_token: "token-c", user: { id: "student-c", email: "student.c@vit.edu" } } });
    await settle();
    harnessC.get("browseNav").dispatch("click");
    await settle();
    const cardC = findCardForTitle(harnessC.get("resourceGrid"), "Algorithms");
    assert.equal(findButton(cardC, "Delete"), null, "Unrelated Account C must not see Delete button");
});
