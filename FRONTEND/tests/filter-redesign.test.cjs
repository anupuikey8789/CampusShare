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

const sampleListings = [
    { id: 101, title: "Data Structures in C++", description: "Standard textbook with exercises", category_id: 1, owner_id: "user-1", resource_type: "book", availability_status: "available", listing_mode: "sell", sale_price: 450, item_condition: "like_new", created_at: "2026-11-01T10:00:00Z" },
    { id: 102, title: "Arduino Starter Kit", description: "Microcontroller board and sensors", category_id: 2, owner_id: "user-2", resource_type: "equipment", availability_status: "available", listing_mode: "sell", sale_price: 1200, item_condition: "new", created_at: "2026-11-05T12:00:00Z" },
    { id: 103, title: "Graphing Calculator TI-84", description: "Advanced engineering calculator", category_id: 2, owner_id: "user-3", resource_type: "equipment", availability_status: "available", listing_mode: "sell", sale_price: 3500, item_condition: "good", created_at: "2026-11-03T08:00:00Z" },
    { id: 104, title: "Engineering Physics Notes", description: "Handwritten semester 1 notes", category_id: 3, owner_id: "user-1", resource_type: "notes", availability_status: "available", listing_mode: "borrow", borrow_price_kind: "free", sale_price: null, item_condition: "fair", created_at: "2026-10-25T14:00:00Z" },
    { id: 105, title: "Organic Chemistry Molecular Model", description: "Plastic ball and stick kit", category_id: 4, owner_id: "user-4", resource_type: "equipment", availability_status: "unavailable", listing_mode: "donate", sale_price: null, item_condition: "good", created_at: "2026-11-08T09:00:00Z" },
    { id: 106, title: "Digital Multimeter Fluke", description: "Precision electrical measurement tool", category_id: 2, owner_id: "user-5", resource_type: "equipment", availability_status: "available", listing_mode: "sell", sale_price: 5500, item_condition: "new", created_at: "2026-11-12T16:00:00Z" },
    { id: 107, title: "Linear Algebra Solutions", description: "Problem set solutions and exam review", category_id: 1, owner_id: "user-2", resource_type: "notes", availability_status: "available", listing_mode: "sell", sale_price: 150, item_condition: "good", created_at: "2026-11-04T11:00:00Z" }
];

test("1. Category only filter returns only items in that category", () => {
    const res = ui.filterResources(sampleListings, { categoryId: "2" });
    assert.deepEqual(res.map(r => r.id), [106, 102, 103]);
});

test("2. Condition only filter matches exact item_condition", () => {
    const res = ui.filterResources(sampleListings, { condition: "new" });
    assert.deepEqual(res.map(r => r.id), [106, 102]);
});

test("3. Price only filter correctly enforces min and max in INR", () => {
    // ₹500 to ₹2,000 range
    const res = ui.filterResources(sampleListings, { listingMode: "sell", minPrice: 500, maxPrice: 2000 });
    assert.deepEqual(res.map(r => r.id), [102]);
    assert.equal(res[0].sale_price, 1200);
});

test("4. Sorting only works for all 6 required sort orders", () => {
    // 4a. Price: Low to High
    const pLow = ui.filterResources(sampleListings, { listingMode: "sell", sort: "price-low" });
    assert.deepEqual(pLow.map(r => r.sale_price), [150, 450, 1200, 3500, 5500]);

    // 4b. Price: High to Low
    const pHigh = ui.filterResources(sampleListings, { listingMode: "sell", sort: "price-high" });
    assert.deepEqual(pHigh.map(r => r.sale_price), [5500, 3500, 1200, 450, 150]);

    // 4c. Alphabetical: A to Z
    const aToZ = ui.filterResources(sampleListings, { sort: "title" });
    assert.equal(aToZ[0].title, "Arduino Starter Kit");
    assert.equal(aToZ[aToZ.length - 1].title, "Organic Chemistry Molecular Model");

    // 4d. Alphabetical: Z to A
    const zToA = ui.filterResources(sampleListings, { sort: "title-desc" });
    assert.equal(zToA[0].title, "Organic Chemistry Molecular Model");
    assert.equal(zToA[zToA.length - 1].title, "Arduino Starter Kit");

    // 4e. Newest First
    const newest = ui.filterResources(sampleListings, { sort: "newest" });
    assert.equal(newest[0].id, 106); // 2026-11-12

    // 4f. Oldest First
    const oldest = ui.filterResources(sampleListings, { sort: "oldest" });
    assert.equal(oldest[0].id, 104); // 2026-10-25
});

test("5. Search only matches title and description case-insensitively", () => {
    const titleMatch = ui.filterResources(sampleListings, { query: "starter kit" });
    assert.deepEqual(titleMatch.map(r => r.id), [102]);

    const descMatch = ui.filterResources(sampleListings, { query: "handwritten" });
    assert.deepEqual(descMatch.map(r => r.id), [104]);

    const mixedCase = ui.filterResources(sampleListings, { query: "pReCiSiOn" });
    assert.deepEqual(mixedCase.map(r => r.id), [106]);
});

test("6. Category + Condition work simultaneously", () => {
    const res = ui.filterResources(sampleListings, { categoryId: "2", condition: "good" });
    assert.deepEqual(res.map(r => r.id), [103]);
});

test("7. Category + Price work simultaneously", () => {
    const res = ui.filterResources(sampleListings, { listingMode: "sell", categoryId: "1", minPrice: 100, maxPrice: 300 });
    assert.deepEqual(res.map(r => r.id), [107]);
    assert.equal(res[0].sale_price, 150);
});

test("8. Condition + Price work simultaneously", () => {
    const res = ui.filterResources(sampleListings, { listingMode: "sell", condition: "like_new", minPrice: 400, maxPrice: 600 });
    assert.deepEqual(res.map(r => r.id), [101]);
});

test("9. Search + Sorting work simultaneously", () => {
    const res = ui.filterResources(sampleListings, { query: "notes", sort: "oldest" });
    assert.deepEqual(res.map(r => r.id), [104, 107]);
});

test("10. All filters together (Category + Condition + Price + Query + Sort)", () => {
    const res = ui.filterResources(sampleListings, {
        listingMode: "sell",
        categoryId: "2",
        condition: "new",
        minPrice: 1000,
        maxPrice: 6000,
        query: "microcontroller",
        sort: "price-low"
    });
    assert.deepEqual(res.map(r => r.id), [102]);
});

test("11. Reset all filters restores full available list", () => {
    const filtered = ui.filterResources(sampleListings, { query: "Arduino", condition: "new" });
    assert.equal(filtered.length, 1);

    const reset = ui.filterResources(sampleListings, { query: "", categoryId: "all", condition: "all", minPrice: null, maxPrice: null });
    assert.equal(reset.length, sampleListings.length);
});

test("12. Remove individual filter chip adjusts results correctly", () => {
    // Start with Category 2 + Condition new
    const both = ui.filterResources(sampleListings, { categoryId: "2", condition: "new" });
    assert.deepEqual(both.map(r => r.id), [106, 102]);

    // Remove condition filter chip (keep Category 2)
    const categoryOnly = ui.filterResources(sampleListings, { categoryId: "2", condition: "all" });
    assert.deepEqual(categoryOnly.map(r => r.id), [106, 102, 103]);

    // Remove category filter chip (keep Condition new)
    const conditionOnly = ui.filterResources(sampleListings, { categoryId: "all", condition: "new" });
    assert.deepEqual(conditionOnly.map(r => r.id), [106, 102]);
});

test("13. Empty results handle non-matching criteria without errors", () => {
    const res = ui.filterResources(sampleListings, { query: "quantum teleportation device" });
    assert.equal(res.length, 0);
});

test("14. Missing condition information handled gracefully", () => {
    const withoutCondition = [
        ...sampleListings,
        { id: 999, title: "Unspecified Item", description: "No condition", category_id: 1, item_condition: null, listing_mode: "sell", sale_price: 100, availability_status: "available", created_at: "2026-11-13T00:00:00Z" }
    ];
    // Filtering by condition "new" excludes item with null condition
    const res = ui.filterResources(withoutCondition, { condition: "new" });
    assert.equal(res.some(r => r.id === 999), false);

    // Filtering by "all" includes it
    const all = ui.filterResources(withoutCondition, { condition: "all" });
    assert.equal(all.some(r => r.id === 999), true);
});

test("15. Missing price handled consistently during numeric sort", () => {
    const mixedPrices = [
        { id: 1, title: "Priced 100", listing_mode: "sell", sale_price: 100, created_at: "2026-11-01T00:00:00Z" },
        { id: 2, title: "Priceless Free", listing_mode: "borrow", borrow_price_kind: "free", sale_price: null, created_at: "2026-11-02T00:00:00Z" },
        { id: 3, title: "Priced 500", listing_mode: "sell", sale_price: 500, created_at: "2026-11-03T00:00:00Z" }
    ];
    const sortedLow = ui.filterResources(mixedPrices, { sort: "price-low" });
    assert.equal(sortedLow[0].id, 2); // 0 price first
    assert.equal(sortedLow[1].id, 1); // 100
    assert.equal(sortedLow[2].id, 3); // 500
});

test("16. Borrow page respects borrow listing mode and condition", () => {
    const res = ui.filterResources(sampleListings, { listingMode: "borrow" });
    assert.deepEqual(res.map(r => r.id), [104]);
});

test("17. Sell page respects sell listing mode with price filters", () => {
    const res = ui.filterResources(sampleListings, { listingMode: "sell", minPrice: 3000 });
    assert.deepEqual(res.map(r => r.id), [106, 103]);
});

test("18. Donate page respects donate listing mode", () => {
    const res = ui.filterResources(sampleListings, { listingMode: "donate" });
    assert.deepEqual(res.map(r => r.id), [105]);
});

test("19. Desktop layout has all required Amazon-inspired filter DOM elements", () => {
    const html = fs.readFileSync(path.join(frontend, "index.html"), "utf8");
    const requiredElements = [
        'id="searchInput"',
        'id="searchClearBtn"',
        'id="openFilterBtn"',
        'id="filterBadge"',
        'id="filterDrawer"',
        'id="filterDrawerBackdrop"',
        'id="filterDrawerTitle"',
        'id="closeFilterBtn"',
        'id="drawerCategorySection"',
        'id="drawerCategoryList"',
        'id="drawerConditionSection"',
        'id="drawerConditionList"',
        'id="drawerPriceSection"',
        'id="drawerQuickPrices"',
        'id="drawerPriceMin"',
        'id="drawerPriceMax"',
        'id="priceSliderMin"',
        'id="priceSliderMax"',
        'id="drawerSortSection"',
        'id="drawerSortList"',
        'id="drawerAvailabilitySection"',
        'id="drawerAvailabilityList"',
        'id="drawerResetBtn"',
        'id="drawerApplyBtn"',
        'id="activeFiltersBar"',
        'id="activeFilterChips"',
        'id="clearFilters"'
    ];
    for (const elem of requiredElements) {
        assert.ok(html.includes(elem), `index.html is missing ${elem}`);
    }
});

test("20. Responsive styling covers drawer slide-in and mobile adaptation", () => {
    const css = fs.readFileSync(path.join(frontend, "style.css"), "utf8");
    assert.ok(css.includes(".filter-drawer"), "style.css missing .filter-drawer");
    assert.ok(css.includes(".filter-drawer.is-open"), "style.css missing .filter-drawer.is-open");
    assert.ok(css.includes(".price-slider-wrap"), "style.css missing .price-slider-wrap");
    assert.ok(css.includes(".filter-chip"), "style.css missing .filter-chip");
    assert.ok(css.includes("@media (max-width: 640px)"), "style.css missing mobile @media rule");
});

test("21. Filter Drawer includes Listing Mode section for My Borrow / My Sell / My Donate filtering", () => {
    const html = fs.readFileSync(path.join(frontend, "index.html"), "utf8");
    const requiredElements = [
        'id="drawerListingModeSection"',
        'id="drawerListingModeTitle"',
        'id="drawerListingModeList"',
        'id="drawerModeAll"',
        'id="drawerModeBorrow"',
        'id="drawerModeSell"',
        'id="drawerModeDonate"'
    ];
    for (const elem of requiredElements) {
        assert.ok(html.includes(elem), `index.html is missing ${elem}`);
    }
});

test("22. My Resources page header is clean and unified without redundant duplicate headings", () => {
    const html = fs.readFileSync(path.join(frontend, "index.html"), "utf8");
    const css = fs.readFileSync(path.join(frontend, "style.css"), "utf8");
    // Verify myResourcesPage mounts resourcesSection without duplicate visible section headings
    assert.ok(!html.includes('class="my-resources-header"'), "Duplicate visible .my-resources-header must be removed from index.html");
    assert.ok(html.includes('id="myBorrowTab"'), "myBorrowTab must be preserved for compatibility");
    assert.ok(html.includes('id="mySellTab"'), "mySellTab must be preserved for compatibility");
    assert.ok(html.includes('id="myDonateTab"'), "myDonateTab must be preserved for compatibility");
    assert.ok(css.includes(".my-resources-header"), "style.css ensures .my-resources-header is suppressed");
});
