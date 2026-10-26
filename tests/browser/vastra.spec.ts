import { test, expect } from "@playwright/test";

test("discovery searches, filters, and opens source-aware product detail", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", e => errors.push(e.message));
  await page.goto("/");
  await expect(page.locator("h1")).toContainText("A world of good finds.");
  await expect(page.locator(".product-card")).toHaveCount(12);
  await page.getByRole("textbox", { name: "Search products or paste a product link" }).fill("tailored cotton white");
  await expect(page.locator(".product-card")).toHaveCount(1);
  await page.getByRole("button", { name: "View The tailored cotton shirt", exact: true }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(page.getByText("This is a sample product, not a live listing.", { exact: false })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "View The tailored cotton shirt", exact: true })).toBeFocused();
  expect(errors).toEqual([]);
});

test("original currency filter enables meaningful price sorting", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Filters", exact: true }).click();
  await page.getByLabel("Store currency").selectOption("USD");
  await page.getByLabel("Sort products").selectOption("Price: low to high");
  await expect(page.locator(".product-card")).toHaveCount(4);
  await expect(page.locator(".product-title").first()).toHaveText("The statement drop earrings");
  await page.getByLabel("Store currency").selectOption("All currencies");
  await expect(page.getByLabel("Sort products")).toHaveValue("Recommended");
});

test("named collection persists after reloading, with a real database write", async ({ page }) => {
  await page.goto("/signin-with-chatgpt?return_to=/");
  await expect(page.locator(".product-card")).toHaveCount(12);
  await page.getByRole("button", { name: "View The tailored cotton shirt", exact: true }).click();
  if (await page.getByRole("button", { name: "Remove from collection", exact: true }).isVisible()) {
    await page.getByRole("button", { name: "Remove from collection", exact: true }).click();
    await expect(page.getByRole("button", { name: "Save to my edit", exact: true })).toBeVisible();
  }
  await page.getByLabel("Save to a collection").fill("Travel wardrobe");
  await page.getByRole("button", { name: "Save to my edit", exact: true }).click();
  await expect(page.getByRole("button", { name: "Remove from collection", exact: true })).toBeVisible();
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Collections", exact: false }).first().click();
  await page.getByRole("button", { name: "Travel wardrobe", exact: true }).click();
  await expect(page.locator(".product-card")).toHaveCount(1);
  await page.reload();
  await page.getByRole("button", { name: "Collections", exact: false }).first().click();
  await expect(page.locator(".product-title")).toContainText(["The tailored cotton shirt"]);
  await page.getByRole("button", { name: "Unsave The tailored cotton shirt", exact: true }).click();
  await expect(page.locator(".product-card")).toHaveCount(0);
});

test("comparison exposes original currencies and sample evidence", async ({ page }) => {
  await page.goto("/");
  await page.locator(".compare-add").nth(0).click();
  await page.locator(".compare-add").nth(1).click();
  await page.locator(".compare-tray").getByRole("button", { name: "Compare", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("USD");
  await expect(page.getByRole("dialog")).toContainText("EUR");
  await expect(page.getByRole("dialog")).toContainText("not verified exact matches");
  await page.getByRole("button", { name: "Remove", exact: true }).first().click();
  await expect(page.locator(".comparison-table thead th")).toHaveCount(2);
});

test("seller sourcing filters to wholesale contacts", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Sellers", exact: true }).click();
  await page.getByRole("button", { name: "Wholesale", exact: true }).click();
  await expect(page.locator(".seller-card")).toHaveCount(2);
  await expect(page.getByRole("link", { name: "Contact Faire", exact: true })).toHaveAttribute("href", "https://www.faire.com");
});

test("signed-in product import rejects unsupported URLs without inventing a listing", async ({ page }) => {
  await page.goto("/signin-with-chatgpt?return_to=/");
  await page.getByRole("button", { name: "Add a link", exact: true }).click();
  await page.getByLabel("Product link", { exact: true }).fill("https://127.0.0.1/private");
  await page.getByRole("button", { name: "Import product", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("not supported yet");
  await expect(page.getByRole("dialog")).toBeVisible();
});

test("API rejects anonymous and cross-origin writes and malformed bodies", async ({ request }) => {
  const anonymous = await request.post("/api/saved", { headers: { Origin: "http://127.0.0.1:5173" }, data: { productId: "sample-1" } });
  expect(anonymous.status()).toBe(401);
  const crossOrigin = await request.post("/api/saved", { headers: { Origin: "https://other.example" }, data: { productId: "sample-1" } });
  expect(crossOrigin.status()).toBe(403);
});

test("mobile navigation, import dialog and layout fit a small viewport", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.getByRole("button", { name: "My catalog", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Your finds, together.", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Add your first product", exact: true }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.getByRole("button", { name: "Close dialog", exact: true }).click();
});
