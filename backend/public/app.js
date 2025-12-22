const API_URL = "http://localhost:8080";

let token = null;
let user = {};

try {
  token = localStorage.getItem("medeasy_token");
  user = JSON.parse(localStorage.getItem("medeasy_user") || "{}");
} catch (e) {
  console.warn("LocalStorage access failed (likely due to file:// protocol):", e);
}

document.addEventListener("DOMContentLoaded", () => {
  init();
});

function init() {
  // UI Elements
  const authStatus = document.getElementById("auth-status");
  const logsContainer = document.getElementById("logs-container");
  const clearLogsBtn = document.getElementById("clear-logs");
  const tabBtns = document.querySelectorAll(".tab-btn");
  const tabContents = document.querySelectorAll(".tab-content");
  const registerRole = document.getElementById("register-role");
  const ownerFields = document.getElementById("owner-fields");
  const employeeFields = document.getElementById("employee-fields");
  const employeePharmacyInput = employeeFields?.querySelector("input[name='pharmacy_id']");

  updateAuthStatus(authStatus);
  setupTabs(tabBtns, tabContents);
  setupForms();

  // Role toggle for register
  if (registerRole && ownerFields) {
    const toggleFields = () => {
      const isOwner = registerRole.value === "owner";
      ownerFields.style.display = isOwner ? "block" : "none";
      if (employeeFields) employeeFields.style.display = isOwner ? "none" : "block";
      if (employeePharmacyInput) employeePharmacyInput.required = !isOwner;
    };
    registerRole.addEventListener("change", toggleFields);
    toggleFields();
  }

  // Add sale item button
  const addSaleItemBtn = document.getElementById("add-sale-item-btn");
  if (addSaleItemBtn) {
    addSaleItemBtn.addEventListener("click", () => {
      const container = document.getElementById("sale-items-container");
      if (!container) return;

      const div = document.createElement("div");
      div.className = "sale-item-row";
      div.innerHTML = `
        <input type="number" placeholder="Inventory ID" class="item-inventory-id" required>
        <input type="number" placeholder="Med ID (optional)" class="item-med-id">
        <input type="number" placeholder="Qty" class="item-qty" required>
      `;
      container.appendChild(div);
    });
  }

  if (clearLogsBtn) {
    clearLogsBtn.addEventListener("click", () => {
      if (logsContainer) logsContainer.innerHTML = "";
    });
  }
}

function updateAuthStatus(authStatus) {
  if (!authStatus) return;

  if (token) {
    authStatus.textContent = `Authenticated as ${user.username || "User"} (${user.role || "unknown"})`;
    authStatus.classList.remove("disconnected");
    authStatus.classList.add("connected");
  } else {
    authStatus.textContent = "Not Authenticated";
    authStatus.classList.remove("connected");
    authStatus.classList.add("disconnected");
  }
}

function setupTabs(tabBtns, tabContents) {
  tabBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      tabBtns.forEach((b) => b.classList.remove("active"));
      tabContents.forEach((c) => c.classList.remove("active"));

      btn.classList.add("active");
      const targetId = btn.dataset.tab;
      const targetContent = document.getElementById(targetId);
      if (targetContent) targetContent.classList.add("active");
    });
  });
}

function log(type, method, url, data) {
  const logsContainer = document.getElementById("logs-container");
  if (!logsContainer) return;

  const entry = document.createElement("div");
  entry.className = `log-entry ${type}`;

  const time = new Date().toLocaleTimeString();
  const header = `<div class="log-header">
      <span class="log-method">${method} ${url}</span>
      <span>${time}</span>
    </div>`;

  const content = `<pre>${escapeHtml(JSON.stringify(data, null, 2))}</pre>`;

  entry.innerHTML = header + content;
  logsContainer.prepend(entry);
}

function escapeHtml(str) {
  return String(str)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

async function apiCall(endpoint, method = "GET", body = null) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const options = { method, headers };
  if (body) options.body = JSON.stringify(body);

  try {
    const res = await fetch(`${API_URL}${endpoint}`, options);

    // Some APIs return empty body for 204, etc.
    let data = null;
    const text = await res.text();
    data = text ? JSON.parse(text) : {};

    if (!res.ok) {
      log("error", method, endpoint, data);
      throw new Error(data.error || `API Error (${res.status})`);
    }

    log("success", method, endpoint, data);
    return data;
  } catch (err) {
    console.error(err);
    log("error", method, endpoint, { error: err.message || "Request failed" });
    return null;
  }
}

function setupForms() {
  const forms = [
    { id: "register-form", url: "/auth/register", method: "POST", authUpdate: true, numeric: ["pharmacy_id"] },
    { id: "login-form", url: "/auth/login", method: "POST", authUpdate: true },
    { id: "reset-password-form", url: "/auth/reset-password", method: "POST" },
    { id: "create-pharmacy-form", url: "/pharmacies", method: "POST" },
    { id: "update-pharmacy-form", url: "/pharmacies/:id", method: "PUT", hasId: true },
    { id: "search-medicine-form", url: "/medicines", method: "GET", query: true },
    { id: "add-inventory-form", url: "/inventory", method: "POST", numeric: ["medicine_id", "quantity"], float: ["cost_price", "sale_price"] },
    { id: "update-inventory-form", url: "/inventory/:id", method: "PUT", hasId: true, numeric: ["medicine_id", "quantity"], float: ["cost_price", "sale_price"] },
    { id: "update-stock-form", url: "/inventory/:id/stock", method: "POST", hasId: true, numeric: ["quantity"] },
    { id: "expiry-alert-form", url: "/inventory/expiry-alert", method: "GET", query: true },
    { id: "daily-sales-form", url: "/reports/sales/daily", method: "GET", query: true },
    { id: "monthly-sales-form", url: "/reports/sales/monthly", method: "GET", query: true },
    { id: "search-inventory-form", url: "/inventory/search", method: "GET", query: true },
    { id: "sales-report-form", url: "/reports/sales", method: "GET", query: true },
  ];

  forms.forEach((config) => {
    const form = document.getElementById(config.id);
    if (!form) return;

    form.addEventListener("submit", async (e) => {
      e.preventDefault();

      const formData = new FormData(e.target);
      let data = Object.fromEntries(formData.entries());
      let url = config.url;

      // Handle ID in URL
      if (config.hasId) {
        const id = data.id;
        delete data.id;
        url = url.replace(":id", id);
      }

      // Handle Query Params
      if (config.query) {
        const params = new URLSearchParams(data).toString();
        url = params ? `${url}?${params}` : url;
        await apiCall(url, config.method);
        return;
      }

      // Numeric/Float conversions
      if (config.numeric) {
        config.numeric.forEach((field) => {
          if (data[field] !== undefined && data[field] !== "") data[field] = parseInt(data[field], 10);
        });
      }
      if (config.float) {
        config.float.forEach((field) => {
          if (data[field] !== undefined && data[field] !== "") data[field] = parseFloat(data[field]);
        });
      }

      // Special handling for Register
      if (config.id === "register-form" && data.role !== "owner") {
        delete data.pharmacy_name;
        delete data.pharmacy_address;
        delete data.pharmacy_location;
      } else if (config.id === "register-form" && data.role === "owner") {
        delete data.pharmacy_id;
      }

      const res = await apiCall(url, config.method, data);

      if (res && config.authUpdate) {
        token = res.token;
        user = res.user;

        try {
          localStorage.setItem("medeasy_token", token);
          localStorage.setItem("medeasy_user", JSON.stringify(user));
        } catch (e) {
          console.warn("LocalStorage write failed:", e);
        }

        updateAuthStatus(document.getElementById("auth-status"));
      }
    });
  });

  // List Pharmacies Button
  const listPharmaciesBtn = document.getElementById("list-pharmacies-btn");
  if (listPharmaciesBtn) {
    listPharmaciesBtn.addEventListener("click", async () => {
      await apiCall("/pharmacies", "GET");
    });
  }

  // Create Sale Form (Complex logic)
  const createSaleForm = document.getElementById("create-sale-form");
  if (createSaleForm) {
    createSaleForm.addEventListener("submit", async (e) => {
      e.preventDefault();

      const formData = new FormData(e.target);

      const items = [];
      document.querySelectorAll(".sale-item-row").forEach((row) => {
        const inventoryId = row.querySelector(".item-inventory-id")?.value;
        const medId = row.querySelector(".item-med-id")?.value;
        const qty = row.querySelector(".item-qty")?.value;
        if (inventoryId && qty) {
          const item = {
            inventory_id: parseInt(inventoryId, 10),
            quantity: parseInt(qty, 10),
          };
          if (medId) item.medicine_id = parseInt(medId, 10);
          items.push(item);
        }
      });

      const data = {
        discount: parseFloat(formData.get("discount") || 0),
        paid_amount: parseFloat(formData.get("paid_amount")),
        items,
      };

      await apiCall("/sales", "POST", data);
    });
  }
}
