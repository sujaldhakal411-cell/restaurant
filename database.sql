-- ================================================================
-- OLD DURBAR HOTEL — Supabase Database Schema
-- ================================================================
-- Run this in: Supabase Dashboard → SQL Editor → New Query → Run
-- ================================================================


-- ──────────────────────────────────────────────────────────────
-- TABLE: orders
-- Stores every customer order placed from the website.
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.orders (
  -- Primary key — Supabase auto-increments this
  id                   BIGSERIAL PRIMARY KEY,

  -- Customer details
  customer_name        TEXT        NOT NULL,
  phone                TEXT        NOT NULL,
  email                TEXT,                          -- optional
  address              TEXT,                          -- optional delivery address

  -- Order metadata
  order_type           TEXT        NOT NULL
    CHECK (order_type IN ('dine-in', 'takeaway', 'delivery')),

  -- Items are stored as a JSONB array:
  --   [ { "id": 1, "name": "Chicken Thali", "price": 250, "quantity": 2 }, … ]
  items                JSONB       NOT NULL DEFAULT '[]'::jsonb,

  -- Computed total (stored for fast queries; sum of price*quantity)
  total                NUMERIC(10,2) NOT NULL DEFAULT 0,

  -- Order lifecycle status
  status               TEXT        NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'preparing', 'ready', 'completed', 'cancelled')),

  -- Payment info
  payment_method       TEXT
    CHECK (payment_method IN ('cash', 'esewa', 'khalti', 'bank')),
  payment_status       TEXT        NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid', 'paid', 'refunded')),

  -- Misc
  special_instructions TEXT,

  -- Timestamps (managed automatically by Supabase trigger below)
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ──────────────────────────────────────────────────────────────
-- AUTO-UPDATE updated_at on any row change
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE PROCEDURE public.set_updated_at();


-- ──────────────────────────────────────────────────────────────
-- INDEXES for common query patterns
-- ──────────────────────────────────────────────────────────────

-- Filter by status (Kanban board / dashboard filter)
CREATE INDEX IF NOT EXISTS idx_orders_status
  ON public.orders (status);

-- Filter / search by phone (order tracking page)
CREATE INDEX IF NOT EXISTS idx_orders_phone
  ON public.orders (phone);

-- Sort by newest first (dashboard default view)
CREATE INDEX IF NOT EXISTS idx_orders_created_at
  ON public.orders (created_at DESC);

-- Full-text search on customer name
CREATE INDEX IF NOT EXISTS idx_orders_customer_name
  ON public.orders USING GIN (to_tsvector('english', customer_name));


-- ──────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY (RLS)
-- ──────────────────────────────────────────────────────────────
-- Enable RLS
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Policy 1: Anyone (anon key) can INSERT a new order (place order from website)
CREATE POLICY "Allow public insert"
  ON public.orders FOR INSERT
  TO anon
  WITH CHECK (true);

-- Policy 2: Anyone can SELECT their own orders by phone
--           (used on the customer "My Orders" tracking page)
CREATE POLICY "Allow select by phone"
  ON public.orders FOR SELECT
  TO anon
  USING (true);   -- You can restrict to: phone = current_setting('app.phone', true)

-- Policy 3: Authenticated users (admin dashboard) can do everything
CREATE POLICY "Allow full access for authenticated"
  ON public.orders FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);


-- ──────────────────────────────────────────────────────────────
-- SAMPLE DATA — uncomment to seed demo orders
-- ──────────────────────────────────────────────────────────────
/*
INSERT INTO public.orders
  (customer_name, phone, email, address, order_type, items, total, status, payment_method, payment_status)
VALUES
  (
    'Hari Prasad Sharma',
    '9801234567',
    'hari@example.com',
    'Antidiene, Itahari',
    'delivery',
    '[{"id":1,"name":"Chicken Thali","price":250,"quantity":2},
      {"id":5,"name":"Masala Tea","price":40,"quantity":2}]'::jsonb,
    580,
    'pending',
    'cash',
    'unpaid'
  ),
  (
    'Sita Devi Rai',
    '9807654321',
    null,
    null,
    'dine-in',
    '[{"id":3,"name":"Buff Momo (12)","price":180,"quantity":1},
      {"id":8,"name":"Fresh Lime Soda","price":60,"quantity":2}]'::jsonb,
    300,
    'completed',
    'esewa',
    'paid'
  ),
  (
    'Ram Bahadur Thapa',
    '9812345678',
    'ram@example.com',
    'Dharan Road, Itahari',
    'takeaway',
    '[{"id":2,"name":"Dal Bhat Set","price":200,"quantity":3}]'::jsonb,
    600,
    'preparing',
    'khalti',
    'paid'
  );
*/


-- ──────────────────────────────────────────────────────────────
-- USEFUL VIEWS (optional analytics)
-- ──────────────────────────────────────────────────────────────

-- Daily revenue summary
CREATE OR REPLACE VIEW public.daily_revenue AS
SELECT
  DATE(created_at AT TIME ZONE 'Asia/Kathmandu') AS order_date,
  COUNT(*)                                        AS total_orders,
  SUM(total) FILTER (WHERE status != 'cancelled') AS revenue,
  COUNT(*) FILTER (WHERE status = 'completed')    AS completed_orders,
  COUNT(*) FILTER (WHERE status = 'cancelled')    AS cancelled_orders
FROM public.orders
GROUP BY 1
ORDER BY 1 DESC;

-- Popular items (from JSONB)
CREATE OR REPLACE VIEW public.popular_items AS
SELECT
  item->>'name'        AS item_name,
  SUM((item->>'quantity')::int) AS total_qty_sold
FROM public.orders,
     jsonb_array_elements(items) AS item
WHERE status != 'cancelled'
GROUP BY 1
ORDER BY 2 DESC;


-- ================================================================
-- SETUP COMPLETE
-- Your Supabase project URL and anon key go into both HTML files:
--   const SUPABASE_URL     = 'https://YOUR_PROJECT_ID.supabase.co';
--   const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY_HERE';
-- ================================================================
