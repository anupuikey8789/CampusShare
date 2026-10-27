
const searchInput = document.getElementById("searchInput");
const categoryFilter = document.getElementById("categoryFilter");
const sortSelect = document.getElementById("sortSelect");
const resourceGrid = document.getElementById("resourceGrid");
const resourceCount = document.getElementById("resourceCount");
const noResults = document.getElementById("noResults");

const resourceForm = document.getElementById("resourceForm");
const showAddForm = document.getElementById("showAddForm");
const cancelAddForm = document.getElementById("cancelAddForm");

let nextCreated = 4;

function getResourceCards() {
    return Array.from(resourceGrid.querySelectorAll(".resource-card"));
}

function refreshResources() {
    const searchText = searchInput.value.toLowerCase().trim();
    const selectedCategory = categoryFilter.value;
    const sortMode = sortSelect.value;

    const cards = getResourceCards();

    cards.sort(function (a, b) {
        if (sortMode === "title") {
            return a.querySelector("h3").textContent.localeCompare(
                b.querySelector("h3").textContent
            );
        }

        return Number(b.dataset.created) - Number(a.dataset.created);
    });

    cards.forEach(function (card) {
        resourceGrid.appendChild(card);
    });

    let visibleCount = 0;

    cards.forEach(function (card) {
        const text = card.textContent.toLowerCase();
        const matchesSearch = text.includes(searchText);
        const matchesCategory =
            selectedCategory === "all" ||
            card.dataset.category === selectedCategory;

        const visible = matchesSearch && matchesCategory;
        card.hidden = !visible;

        if (visible) visibleCount++;
    });

    resourceCount.textContent =
        `${visibleCount} resource${visibleCount === 1 ? "" : "s"} shown`;

    noResults.hidden = visibleCount !== 0;
}

searchInput.addEventListener("input", refreshResources);
categoryFilter.addEventListener("change", refreshResources);
sortSelect.addEventListener("change", refreshResources);

showAddForm.addEventListener("click", function () {
    resourceForm.hidden = !resourceForm.hidden;
});

cancelAddForm.addEventListener("click", function () {
    resourceForm.reset();
    resourceForm.hidden = true;
});

resourceForm.addEventListener("submit", function (event) {
    event.preventDefault();

    const title = document.getElementById("resourceTitle").value.trim();
    const description =
        document.getElementById("resourceDescription").value.trim();
    const category = document.getElementById("resourceCategory").value;

    if (!title || !description) return;

    const card = document.createElement("article");
    card.className = "resource-card";
    card.dataset.category = category;
    card.dataset.created = String(nextCreated++);

    const icon = document.createElement("div");
    icon.className = "resource-icon";
    icon.textContent = "📚";

    const heading = document.createElement("h3");
    heading.textContent = title;

    const details = document.createElement("p");
    details.textContent = description;

    const badge = document.createElement("span");
    badge.textContent = category;

    card.append(icon, heading, details, badge);
    resourceGrid.prepend(card);

    resourceForm.reset();
    resourceForm.hidden = true;

    // Show the newly added resource even if a previous filter was active.
    searchInput.value = "";
    categoryFilter.value = "all";
    sortSelect.value = "newest";

    refreshResources();
});

refreshResources();
