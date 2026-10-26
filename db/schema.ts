import { sqliteTable, text, integer, primaryKey, index, uniqueIndex } from "drizzle-orm/sqlite-core";

// User-owned products keep source evidence and distinct seller offers.
export const products = sqliteTable("products", {
  id: text("id").primaryKey(),
  ownerId: text("owner_id").notNull(),
  sourceUrl: text("source_url").notNull(),
  document: text("document").notNull(),
  createdAt: integer("created_at").notNull(),
}, table => [index("products_owner").on(table.ownerId), uniqueIndex("products_owner_source").on(table.ownerId, table.sourceUrl)]);

export const saved = sqliteTable("saved", {
  ownerId: text("owner_id").notNull(),
  productId: text("product_id").notNull(),
  collection: text("collection").notNull().default("My edit"),
  createdAt: integer("created_at").notNull(),
}, table => [primaryKey({ columns: [table.ownerId, table.productId] })]);
