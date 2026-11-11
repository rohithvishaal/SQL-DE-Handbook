-- ============================================================================
-- Project 1: Clickstream Sessionization & Multi-Touch Attribution
-- Seed Data — Realistic mock data for all tables
-- ============================================================================

-- --------------------------------------------------------------------------
-- Marketing Channels (reference data — 10 rows)
-- --------------------------------------------------------------------------
INSERT INTO marketing_channels (channel_id, utm_source, utm_medium, channel_name, channel_group) VALUES
(1,  'google',    'cpc',      'Paid Search',       'paid'),
(2,  'google',    'organic',  'Organic Search',     'organic'),
(3,  'facebook',  'cpc',      'Paid Social',        'paid'),
(4,  'facebook',  'social',   'Organic Social',     'organic'),
(5,  'newsletter','email',    'Email Marketing',    'owned'),
(6,  'bing',      'cpc',      'Paid Search - Bing', 'paid'),
(7,  'twitter',   'social',   'Organic Social - X', 'organic'),
(8,  'instagram', 'cpc',      'Paid Social - IG',   'paid'),
(9,  'direct',    'none',     'Direct',             'direct'),
(10, 'partner',   'referral', 'Affiliate/Referral', 'referral');

-- --------------------------------------------------------------------------
-- Raw Clicks (60 rows — 4 users, multiple sessions, varied channels)
-- --------------------------------------------------------------------------

-- === User U001 — Session 1 (Paid Search → Browse → Purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-001', 'U001', '2024-03-15 10:00:00', 'page_view', '/landing/spring-sale',    'https://google.com',   'google',   'cpc',     'spring_sale_2024', 'desktop', 'US'),
('evt-002', 'U001', '2024-03-15 10:02:30', 'page_view', '/category/electronics',   NULL,                   NULL,       NULL,      NULL,               'desktop', 'US'),
('evt-003', 'U001', '2024-03-15 10:05:15', 'page_view', '/product/laptop-pro-15',  NULL,                   NULL,       NULL,      NULL,               'desktop', 'US'),
('evt-004', 'U001', '2024-03-15 10:06:00', 'click',     '/product/laptop-pro-15',  NULL,                   NULL,       NULL,      NULL,               'desktop', 'US'),
('evt-005', 'U001', '2024-03-15 10:08:45', 'add_to_cart','/product/laptop-pro-15', NULL,                   NULL,       NULL,      NULL,               'desktop', 'US'),
('evt-006', 'U001', '2024-03-15 10:12:00', 'page_view', '/cart',                   NULL,                   NULL,       NULL,      NULL,               'desktop', 'US'),
('evt-007', 'U001', '2024-03-15 10:15:30', 'page_view', '/checkout',               NULL,                   NULL,       NULL,      NULL,               'desktop', 'US'),
('evt-008', 'U001', '2024-03-15 10:18:00', 'purchase',  '/order-confirmation',     NULL,                   NULL,       NULL,      NULL,               'desktop', 'US');

-- === User U001 — Session 2 (45 min gap → Email → Browse only, no purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-009', 'U001', '2024-03-15 11:05:00', 'page_view', '/deals',                  'https://mail.google.com', 'newsletter', 'email', 'weekly_deals', 'desktop', 'US'),
('evt-010', 'U001', '2024-03-15 11:08:00', 'page_view', '/product/headphones-bt',  NULL,                   NULL,       NULL,      NULL,               'desktop', 'US'),
('evt-011', 'U001', '2024-03-15 11:10:30', 'click',     '/product/headphones-bt',  NULL,                   NULL,       NULL,      NULL,               'desktop', 'US');

-- === User U002 — Session 1 (Organic Social → Browse → Leave) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-012', 'U002', '2024-03-15 09:00:00', 'page_view', '/blog/top-10-gadgets',    'https://facebook.com', 'facebook', 'social',  NULL,               'mobile',  'UK'),
('evt-013', 'U002', '2024-03-15 09:04:00', 'page_view', '/product/smartwatch-x',   NULL,                   NULL,       NULL,      NULL,               'mobile',  'UK'),
('evt-014', 'U002', '2024-03-15 09:05:30', 'click',     '/product/smartwatch-x',   NULL,                   NULL,       NULL,      NULL,               'mobile',  'UK');

-- === User U002 — Session 2 (2 hours later, Paid Social → Purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-015', 'U002', '2024-03-15 11:15:00', 'page_view', '/product/smartwatch-x',   'https://facebook.com', 'facebook', 'cpc',     'retarget_march',   'mobile',  'UK'),
('evt-016', 'U002', '2024-03-15 11:17:00', 'add_to_cart','/product/smartwatch-x',  NULL,                   NULL,       NULL,      NULL,               'mobile',  'UK'),
('evt-017', 'U002', '2024-03-15 11:20:00', 'page_view', '/cart',                   NULL,                   NULL,       NULL,      NULL,               'mobile',  'UK'),
('evt-018', 'U002', '2024-03-15 11:23:00', 'page_view', '/checkout',               NULL,                   NULL,       NULL,      NULL,               'mobile',  'UK'),
('evt-019', 'U002', '2024-03-15 11:25:00', 'purchase',  '/order-confirmation',     NULL,                   NULL,       NULL,      NULL,               'mobile',  'UK');

-- === User U003 — Session 1 (Direct → Bounce — single page view) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-020', 'U003', '2024-03-15 14:00:00', 'page_view', '/homepage',               NULL,                   'direct',   'none',    NULL,               'desktop', 'CA');

-- === User U003 — Session 2 (1 hour later, Paid Search → Multi-page → Purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-021', 'U003', '2024-03-15 15:10:00', 'page_view', '/landing/clearance',      'https://bing.com',     'bing',     'cpc',     'clearance_q1',     'desktop', 'CA'),
('evt-022', 'U003', '2024-03-15 15:13:00', 'page_view', '/category/accessories',   NULL,                   NULL,       NULL,      NULL,               'desktop', 'CA'),
('evt-023', 'U003', '2024-03-15 15:16:00', 'page_view', '/product/phone-case-pro', NULL,                   NULL,       NULL,      NULL,               'desktop', 'CA'),
('evt-024', 'U003', '2024-03-15 15:18:00', 'add_to_cart','/product/phone-case-pro',NULL,                   NULL,       NULL,      NULL,               'desktop', 'CA'),
('evt-025', 'U003', '2024-03-15 15:19:00', 'page_view', '/product/screen-guard',   NULL,                   NULL,       NULL,      NULL,               'desktop', 'CA'),
('evt-026', 'U003', '2024-03-15 15:20:30', 'add_to_cart','/product/screen-guard',  NULL,                   NULL,       NULL,      NULL,               'desktop', 'CA'),
('evt-027', 'U003', '2024-03-15 15:22:00', 'page_view', '/cart',                   NULL,                   NULL,       NULL,      NULL,               'desktop', 'CA'),
('evt-028', 'U003', '2024-03-15 15:25:00', 'page_view', '/checkout',               NULL,                   NULL,       NULL,      NULL,               'desktop', 'CA'),
('evt-029', 'U003', '2024-03-15 15:27:00', 'purchase',  '/order-confirmation',     NULL,                   NULL,       NULL,      NULL,               'desktop', 'CA');

-- === User U003 — Session 3 (Next day, Email → Browse → Purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-030', 'U003', '2024-03-16 09:00:00', 'page_view', '/deals/flash-sale',       'https://mail.google.com', 'newsletter', 'email', 'flash_sale_mar', 'tablet', 'CA'),
('evt-031', 'U003', '2024-03-16 09:03:00', 'page_view', '/product/wireless-mouse', NULL,                   NULL,       NULL,      NULL,               'tablet',  'CA'),
('evt-032', 'U003', '2024-03-16 09:05:00', 'add_to_cart','/product/wireless-mouse',NULL,                   NULL,       NULL,      NULL,               'tablet',  'CA'),
('evt-033', 'U003', '2024-03-16 09:07:00', 'page_view', '/cart',                   NULL,                   NULL,       NULL,      NULL,               'tablet',  'CA'),
('evt-034', 'U003', '2024-03-16 09:10:00', 'purchase',  '/order-confirmation',     NULL,                   NULL,       NULL,      NULL,               'tablet',  'CA');

-- === User U004 — Session 1 (Organic Search → Extensive browsing, no purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-035', 'U004', '2024-03-15 16:00:00', 'page_view', '/blog/best-laptops-2024', 'https://google.com',   'google',   'organic', NULL,               'mobile',  'DE'),
('evt-036', 'U004', '2024-03-15 16:03:00', 'page_view', '/category/laptops',       NULL,                   NULL,       NULL,      NULL,               'mobile',  'DE'),
('evt-037', 'U004', '2024-03-15 16:06:00', 'page_view', '/product/laptop-air-13',  NULL,                   NULL,       NULL,      NULL,               'mobile',  'DE'),
('evt-038', 'U004', '2024-03-15 16:08:00', 'click',     '/product/laptop-air-13',  NULL,                   NULL,       NULL,      NULL,               'mobile',  'DE'),
('evt-039', 'U004', '2024-03-15 16:10:00', 'page_view', '/product/laptop-pro-15',  NULL,                   NULL,       NULL,      NULL,               'mobile',  'DE'),
('evt-040', 'U004', '2024-03-15 16:14:00', 'page_view', '/compare?ids=air13,pro15',NULL,                   NULL,       NULL,      NULL,               'mobile',  'DE');

-- === User U004 — Session 2 (Next day, Paid Social IG → Direct purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-041', 'U004', '2024-03-16 12:00:00', 'page_view', '/product/laptop-pro-15',  'https://instagram.com','instagram','cpc',     'ig_laptops_mar',   'desktop', 'DE'),
('evt-042', 'U004', '2024-03-16 12:02:00', 'add_to_cart','/product/laptop-pro-15', NULL,                   NULL,       NULL,      NULL,               'desktop', 'DE'),
('evt-043', 'U004', '2024-03-16 12:04:00', 'page_view', '/cart',                   NULL,                   NULL,       NULL,      NULL,               'desktop', 'DE'),
('evt-044', 'U004', '2024-03-16 12:06:00', 'page_view', '/checkout',               NULL,                   NULL,       NULL,      NULL,               'desktop', 'DE'),
('evt-045', 'U004', '2024-03-16 12:08:00', 'purchase',  '/order-confirmation',     NULL,                   NULL,       NULL,      NULL,               'desktop', 'DE');

-- === User U004 — Session 3 (Same day, 2hr later, Affiliate → Purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-046', 'U004', '2024-03-16 14:30:00', 'page_view', '/product/monitor-4k',     'https://techblog.com', 'partner',  'referral','techblog_spring',  'desktop', 'DE'),
('evt-047', 'U004', '2024-03-16 14:33:00', 'add_to_cart','/product/monitor-4k',    NULL,                   NULL,       NULL,      NULL,               'desktop', 'DE'),
('evt-048', 'U004', '2024-03-16 14:35:00', 'page_view', '/cart',                   NULL,                   NULL,       NULL,      NULL,               'desktop', 'DE'),
('evt-049', 'U004', '2024-03-16 14:37:00', 'purchase',  '/order-confirmation',     NULL,                   NULL,       NULL,      NULL,               'desktop', 'DE');

-- === User U001 — Session 3 (Next day, Twitter → Browse → Email → Purchase — multi-channel session) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-050', 'U001', '2024-03-16 08:00:00', 'page_view', '/blog/spring-trends',     'https://twitter.com',  'twitter',  'social',  NULL,               'mobile',  'US'),
('evt-051', 'U001', '2024-03-16 08:03:00', 'page_view', '/category/shoes',         NULL,                   NULL,       NULL,      NULL,               'mobile',  'US'),
('evt-052', 'U001', '2024-03-16 08:05:00', 'page_view', '/product/running-shoe-v2',NULL,                   NULL,       NULL,      NULL,               'mobile',  'US'),
('evt-053', 'U001', '2024-03-16 08:20:00', 'page_view', '/product/running-shoe-v2','https://mail.google.com','newsletter','email', 'shoe_promo',       'mobile',  'US'),
('evt-054', 'U001', '2024-03-16 08:22:00', 'add_to_cart','/product/running-shoe-v2',NULL,                  NULL,       NULL,      NULL,               'mobile',  'US'),
('evt-055', 'U001', '2024-03-16 08:25:00', 'page_view', '/cart',                   NULL,                   NULL,       NULL,      NULL,               'mobile',  'US'),
('evt-056', 'U001', '2024-03-16 08:28:00', 'purchase',  '/order-confirmation',     NULL,                   NULL,       NULL,      NULL,               'mobile',  'US');

-- === User U002 — Session 3 (Direct visit → Browse → No purchase) ===
INSERT INTO raw_clicks (event_id, user_id, event_timestamp, event_type, page_url, referrer_url, utm_source, utm_medium, utm_campaign, device_type, country_code) VALUES
('evt-057', 'U002', '2024-03-16 17:00:00', 'page_view', '/homepage',               NULL,                   'direct',   'none',    NULL,               'desktop', 'UK'),
('evt-058', 'U002', '2024-03-16 17:03:00', 'page_view', '/category/phones',        NULL,                   NULL,       NULL,      NULL,               'desktop', 'UK'),
('evt-059', 'U002', '2024-03-16 17:07:00', 'page_view', '/product/phone-ultra',    NULL,                   NULL,       NULL,      NULL,               'desktop', 'UK'),
('evt-060', 'U002', '2024-03-16 17:09:00', 'click',     '/product/phone-ultra',    NULL,                   NULL,       NULL,      NULL,               'desktop', 'UK');

-- --------------------------------------------------------------------------
-- Page Views (40 rows — enriched from every page_view event in raw_clicks)
-- --------------------------------------------------------------------------
INSERT INTO page_views (page_view_id, event_id, user_id, view_timestamp, page_url, page_category, product_id, time_on_page_s) VALUES
('pv-001', 'evt-001', 'U001', '2024-03-15 10:00:00', '/landing/spring-sale',     'landing',   NULL,             150),
('pv-002', 'evt-002', 'U001', '2024-03-15 10:02:30', '/category/electronics',    'category',  NULL,             165),
('pv-003', 'evt-003', 'U001', '2024-03-15 10:05:15', '/product/laptop-pro-15',   'product',   'PROD-LP15',      225),
('pv-004', 'evt-006', 'U001', '2024-03-15 10:12:00', '/cart',                    'cart',      NULL,             210),
('pv-005', 'evt-007', 'U001', '2024-03-15 10:15:30', '/checkout',                'checkout',  NULL,             150),
('pv-006', 'evt-009', 'U001', '2024-03-15 11:05:00', '/deals',                   'landing',   NULL,             180),
('pv-007', 'evt-010', 'U001', '2024-03-15 11:08:00', '/product/headphones-bt',   'product',   'PROD-HBT',       150),
('pv-008', 'evt-012', 'U002', '2024-03-15 09:00:00', '/blog/top-10-gadgets',     'blog',      NULL,             240),
('pv-009', 'evt-013', 'U002', '2024-03-15 09:04:00', '/product/smartwatch-x',    'product',   'PROD-SWX',        90),
('pv-010', 'evt-015', 'U002', '2024-03-15 11:15:00', '/product/smartwatch-x',    'product',   'PROD-SWX',       120),
('pv-011', 'evt-017', 'U002', '2024-03-15 11:20:00', '/cart',                    'cart',      NULL,             180),
('pv-012', 'evt-018', 'U002', '2024-03-15 11:23:00', '/checkout',                'checkout',  NULL,             120),
('pv-013', 'evt-020', 'U003', '2024-03-15 14:00:00', '/homepage',                'homepage',  NULL,              15),
('pv-014', 'evt-021', 'U003', '2024-03-15 15:10:00', '/landing/clearance',       'landing',   NULL,             180),
('pv-015', 'evt-022', 'U003', '2024-03-15 15:13:00', '/category/accessories',    'category',  NULL,             180),
('pv-016', 'evt-023', 'U003', '2024-03-15 15:16:00', '/product/phone-case-pro',  'product',   'PROD-PCP',       120),
('pv-017', 'evt-025', 'U003', '2024-03-15 15:19:00', '/product/screen-guard',    'product',   'PROD-SG',         90),
('pv-018', 'evt-027', 'U003', '2024-03-15 15:22:00', '/cart',                    'cart',      NULL,             180),
('pv-019', 'evt-028', 'U003', '2024-03-15 15:25:00', '/checkout',                'checkout',  NULL,             120),
('pv-020', 'evt-030', 'U003', '2024-03-16 09:00:00', '/deals/flash-sale',        'landing',   NULL,             180),
('pv-021', 'evt-031', 'U003', '2024-03-16 09:03:00', '/product/wireless-mouse',  'product',   'PROD-WM',        120),
('pv-022', 'evt-033', 'U003', '2024-03-16 09:07:00', '/cart',                    'cart',      NULL,             180),
('pv-023', 'evt-035', 'U004', '2024-03-15 16:00:00', '/blog/best-laptops-2024',  'blog',      NULL,             180),
('pv-024', 'evt-036', 'U004', '2024-03-15 16:03:00', '/category/laptops',        'category',  NULL,             180),
('pv-025', 'evt-037', 'U004', '2024-03-15 16:06:00', '/product/laptop-air-13',   'product',   'PROD-LA13',      120),
('pv-026', 'evt-039', 'U004', '2024-03-15 16:10:00', '/product/laptop-pro-15',   'product',   'PROD-LP15',      240),
('pv-027', 'evt-040', 'U004', '2024-03-15 16:14:00', '/compare?ids=air13,pro15', 'other',     NULL,             110),
('pv-028', 'evt-041', 'U004', '2024-03-16 12:00:00', '/product/laptop-pro-15',   'product',   'PROD-LP15',      120),
('pv-029', 'evt-043', 'U004', '2024-03-16 12:04:00', '/cart',                    'cart',      NULL,             120),
('pv-030', 'evt-044', 'U004', '2024-03-16 12:06:00', '/checkout',                'checkout',  NULL,             120),
('pv-031', 'evt-046', 'U004', '2024-03-16 14:30:00', '/product/monitor-4k',      'product',   'PROD-M4K',       180),
('pv-032', 'evt-048', 'U004', '2024-03-16 14:35:00', '/cart',                    'cart',      NULL,             120),
('pv-033', 'evt-050', 'U001', '2024-03-16 08:00:00', '/blog/spring-trends',      'blog',      NULL,             180),
('pv-034', 'evt-051', 'U001', '2024-03-16 08:03:00', '/category/shoes',          'category',  NULL,             120),
('pv-035', 'evt-052', 'U001', '2024-03-16 08:05:00', '/product/running-shoe-v2', 'product',   'PROD-RSV2',      900),
('pv-036', 'evt-053', 'U001', '2024-03-16 08:20:00', '/product/running-shoe-v2', 'product',   'PROD-RSV2',      120),
('pv-037', 'evt-055', 'U001', '2024-03-16 08:25:00', '/cart',                    'cart',      NULL,             180),
('pv-038', 'evt-057', 'U002', '2024-03-16 17:00:00', '/homepage',                'homepage',  NULL,             180),
('pv-039', 'evt-058', 'U002', '2024-03-16 17:03:00', '/category/phones',         'category',  NULL,             240),
('pv-040', 'evt-059', 'U002', '2024-03-16 17:07:00', '/product/phone-ultra',     'product',   'PROD-PU',        120);

-- --------------------------------------------------------------------------
-- Purchases (7 orders across 4 users)
-- --------------------------------------------------------------------------
INSERT INTO purchases (order_id, user_id, purchase_timestamp, revenue, item_count) VALUES
('ORD-1001', 'U001', '2024-03-15 10:18:00', 1299.99, 1),   -- U001 Session 1: Laptop
('ORD-1002', 'U002', '2024-03-15 11:25:00',  249.99, 1),   -- U002 Session 2: Smartwatch
('ORD-1003', 'U003', '2024-03-15 15:27:00',   34.98, 2),   -- U003 Session 2: Phone case + screen guard
('ORD-1004', 'U003', '2024-03-16 09:10:00',   29.99, 1),   -- U003 Session 3: Wireless mouse
('ORD-1005', 'U004', '2024-03-16 12:08:00', 1599.99, 1),   -- U004 Session 2: Laptop Pro
('ORD-1006', 'U004', '2024-03-16 14:37:00',  449.99, 1),   -- U004 Session 3: 4K Monitor
('ORD-1007', 'U001', '2024-03-16 08:28:00',  129.99, 1);   -- U001 Session 3: Running shoes
