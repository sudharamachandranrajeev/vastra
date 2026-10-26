CREATE TABLE `products` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_id` text NOT NULL,
	`source_url` text NOT NULL,
	`document` text NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `products_owner` ON `products` (`owner_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `products_owner_source` ON `products` (`owner_id`,`source_url`);--> statement-breakpoint
CREATE TABLE `saved` (
	`owner_id` text NOT NULL,
	`product_id` text NOT NULL,
	`collection` text DEFAULT 'My edit' NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`owner_id`, `product_id`)
);
