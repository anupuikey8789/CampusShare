const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const frontend = path.resolve(__dirname, "..");
const context = {};
context.window = context;
vm.runInNewContext(fs.readFileSync(path.join(frontend, "ui-model.js"), "utf8"), context);
const ui = context.CampusShareUiModel;

const resources = [
    { id: 1, title: "Algorithms", description: "Study notes", category_id: 10, owner_id: "student-a", resource_type: "book", availability_status: "available", created_at: "2026-11-10T00:00:00Z" },
    { id: 2, title: "Lab calculator", description: "Scientific calculator", category_id: 20, owner_id: "student-b", resource_type: "equipment", availability_status: "unavailable", created_at: "2026-11-11T00:00:00Z" },
    { id: 3, title: "Physics review", description: "Exam guide", category_id: 10, owner_id: "student-a", resource_type: "notes", availability_status: "unavailable", created_at: "2026-11-09T00:00:00Z" }
];

test("resource discovery filters search, category, type, availability, and owner", () => {
    assert.deepEqual(ui.filterResources(resources, { query: "calculator" }).map((row) => row.id), [2]);
    assert.deepEqual(ui.filterResources(resources, { resourceType: "equipment" }).map((row) => row.id), [2]);
    assert.deepEqual(ui.filterResources(resources, { query: "equipment" }).map((row) => row.id), [2]);
    assert.deepEqual(ui.filterResources(resources, { categoryId: "10" }).map((row) => row.id), [1, 3]);
    assert.deepEqual(ui.filterResources(resources, { availability: "available" }).map((row) => row.id), [1]);
    assert.deepEqual(ui.filterResources(resources, { ownerId: "student-a" }).map((row) => row.id), [1, 3]);
    assert.deepEqual(ui.filterResources(resources, { ownerId: "student-a", availability: "available" }).map((row) => row.id), [1]);
    assert.deepEqual(ui.filterResources(resources, { sort: "title" }).map((row) => row.title), ["Algorithms", "Lab calculator", "Physics review"]);
});

test("resource discovery can independently filter Borrow, Sell, and Donate listing modes", () => {
    const listings = [
        { ...resources[0], listing_mode: "borrow" },
        { ...resources[1], listing_mode: "sell" },
        { ...resources[2], listing_mode: "donate" }
    ];
    assert.deepEqual(ui.filterResources(listings, { listingMode: "sell" }).map((row) => row.id), [2]);
    assert.deepEqual(ui.filterResources(listings, { listingMode: "donate" }).map((row) => row.id), [3]);
});

test("marketplace discovery filters INR price ranges and sale condition, and sorts by price", () => {
    const listings = [
        { ...resources[0], id: 11, listing_mode: "sell", sale_price: 45, item_condition: "good" },
        { ...resources[1], id: 12, listing_mode: "sell", sale_price: 80, item_condition: "like_new" },
        { ...resources[2], id: 13, listing_mode: "sell", sale_price: 25, item_condition: "fair" },
        { ...resources[0], id: 14, listing_mode: "donate", sale_price: null, item_condition: null }
    ];
    assert.deepEqual(ui.filterResources(listings, { listingMode: "sell", minPrice: "30", maxPrice: "80" }).map((row) => row.id), [12, 11]);
    assert.deepEqual(ui.filterResources(listings, { listingMode: "sell", condition: "good" }).map((row) => row.id), [11]);
    assert.deepEqual(ui.filterResources(listings, { listingMode: "sell", sort: "price-low" }).map((row) => row.id), [13, 11, 12]);
    assert.deepEqual(ui.filterResources(listings, { listingMode: "sell", sort: "price-high" }).map((row) => row.id), [12, 11, 13]);
});

test("dashboard totals and recent listings use only returned records", () => {
    const stats = ui.dashboardStats(resources, [
        { id: 11, status: "pending" }, { id: 12, status: "approved" }, { id: 13, status: "rejected" }
    ], "student-a");
    assert.equal(stats.myResources, 2);
    assert.equal(stats.availableResources, 1);
    assert.equal(stats.pendingRequests, 1);
    assert.equal(stats.approvedRequests, 1);
    assert.deepEqual(stats.recentResources.map((row) => row.id), [1, 3]);
});

test("marketplace dashboard counts only active listings and completed transactions", () => {
    const listings = [
        { id: 1, owner_id: "student-a", listing_mode: "borrow", listing_state: "active" },
        { id: 2, owner_id: "student-a", listing_mode: "sell", listing_state: "sold" },
        { id: 3, owner_id: "student-a", listing_mode: "donate", listing_state: "active" }
    ];
    const stats = ui.dashboardMarketplaceStats(listings,
        [{ id: 10, resource_id: 1, borrower_id: "student-a", status: "returned" }, { id: 11, resource_id: 1, borrower_id: "student-a", status: "rejected" }],
        [{ id: 20, owner_id: "student-a", requester_id: "student-b", request_type: "sell", status: "completed" },
            { id: 21, owner_id: "student-a", requester_id: "student-c", request_type: "donate", status: "rejected" }],
        "student-a");
    assert.equal(stats.activeBorrowListings, 1);
    assert.equal(stats.activeSellListings, 0);
    assert.equal(stats.activeDonateListings, 1);
    assert.equal(stats.completedBorrowReturns, 1);
    assert.equal(stats.completedSales, 1);
    assert.equal(stats.completedDonations, 0);
});

test("borrow actions require availability, a different owner, and enabled flags", () => {
    assert.equal(ui.canRequestBorrow(resources[0], { userId: "student-b", borrowingEnabled: true }), true);
    assert.equal(ui.canRequestBorrow(resources[0], { userId: "student-a", borrowingEnabled: true }), false);
    assert.equal(ui.canRequestBorrow(resources[1], { userId: "student-a", borrowingEnabled: true }), false);
    assert.equal(ui.canRequestBorrow(resources[0], { userId: "student-b", borrowingEnabled: false }), false);
    assert.equal(ui.canRequestBorrow(resources[0], { userId: "student-b", borrowingEnabled: true, hasActiveRequest: true }), false);
});

test("owner status controls are feature-gated and match the request state", () => {
    const pending = { id: 1, status: "pending" };
    const approved = { id: 2, status: "approved" };
    assert.deepEqual(Array.from(ui.ownerRequestActions(pending, { isOwner: true, statusActionsEnabled: false })), []);
    assert.deepEqual(Array.from(ui.ownerRequestActions(pending, { isOwner: false, statusActionsEnabled: true })), []);
    assert.deepEqual(Array.from(ui.ownerRequestActions(pending, { isOwner: true, statusActionsEnabled: true })), ["approve", "reject"]);
    assert.deepEqual(Array.from(ui.ownerRequestActions(approved, { isOwner: true, statusActionsEnabled: true })), ["return"]);
    assert.deepEqual(Array.from(ui.ownerRequestActions({ id: 3, status: "returned" }, { isOwner: true, statusActionsEnabled: true })), []);
    assert.deepEqual(Array.from(ui.ownerRequestActions({ status: "pending" }, { isOwner: true, statusActionsEnabled: true })), []);
});

test("resource form validates required schema-backed fields", () => {
    assert.equal(ui.validateResourcePayload({}), "Enter a resource title.");
    assert.equal(ui.validateResourcePayload({ title: "Book", description: "Notes", category_id: "10", resource_type: "book", availability_status: "borrowed" }), "Choose a valid availability status.");
    assert.equal(ui.validateResourcePayload({ title: " Book ", description: " Notes ", category_id: "10", resource_type: "book", availability_status: "available" }), "");
});

test("page contains dashboard, separate Borrow/Sell/Donate views, price filters, personal listings, and request sections", () => {
    const html = fs.readFileSync(path.join(frontend, "index.html"), "utf8");
    for (const id of ["appSidebar", "sidebarBackdrop", "mobileNavToggle", "topbarPageTitle", "topbarStudentName", "topbarStudentEmail", "authButton", "homeNav", "dashboardNav", "browseNav", "sellNav", "donateNav", "myResourcesNav", "requestsNav", "aboutNav", "home", "dashboard", "browsePage", "sellPage", "donatePage", "myResourcesPage", "browseResourcesMount", "sellResourcesMount", "donateResourcesMount", "myResourcesMount", "borrowRequestsSection", "about", "statMyResources", "marketplaceDashboardSummary", "listingModeFilter", "availabilityFilter", "priceMinFilter", "priceMaxFilter", "conditionFilter", "resourceTypeFilter", "clearFilters", "myBorrowSection", "ownerBorrowSection", "resourceDetailsActions"]) {
        assert.match(html, new RegExp(`id="${id}"`));
    }
    for (const route of ["home", "dashboard", "browse", "my-resources", "borrowing", "about"]) {
        assert.match(html, new RegExp(`data-route-view="${route}"`));
    }
    assert.match(html, /href="#my-resources"/);
    assert.match(html, /href="#borrowing"/);
    const css = fs.readFileSync(path.join(frontend, "style.css"), "utf8");
    assert.match(css, /nav a\[aria-current="page"\]/);
    assert.match(css, /@media \(max-width: 700px\)/);
    assert.match(css, /\.app-sidebar\s*\{[^}]*transform:\s*translateX\(-105%\)/s);
    assert.match(css, /\.app-sidebar\.is-open\s*\{[^}]*transform:\s*translateX\(0\)/s);
    assert.match(css, /\.app-main\s*\{[^}]*margin-left:\s*0/);
    assert.match(css, /\.mobile-nav-toggle\s*\{[^}]*display:\s*inline-grid/);
    assert.match(html, /src="ui-model\.js"/);
    assert.match(html, /id="borrowStatusFeatureNote"[^>]*hidden/);
});

test("every statically referenced app element exists in the page", () => {
    const html = fs.readFileSync(path.join(frontend, "index.html"), "utf8");
    const app = fs.readFileSync(path.join(frontend, "app.js"), "utf8");
    const ids = new Set(Array.from(html.matchAll(/\bid="([^"]+)"/g), (match) => match[1]));
    const references = new Set(Array.from(app.matchAll(/getElementById\("([^"]+)"\)/g), (match) => match[1]));
    const missing = Array.from(references).filter((id) => !ids.has(id));
    assert.deepEqual(missing, []);
});
