-- ══════════════════════════════════════════════════════════════
--  RLS MIGRATION: anon → authenticated
--  EA Sales Intelligence — run once in Supabase SQL Editor
--  Project: rsoukgpaqsgsdfvwrceu
--
--  WHAT THIS DOES:
--    Replaces all open "anon" policies (accessible with just the
--    public anon key) with "authenticated" policies that require
--    the user to be signed in via Supabase Auth.
--
--  PREREQUISITE:
--    You must have at least one Supabase Auth user created.
--    Dashboard → Authentication → Users → Add user
--    (use Carol's email + a strong password)
--
--  HOW TO RUN:
--    Supabase Dashboard → SQL Editor → New query → paste → Run
-- ══════════════════════════════════════════════════════════════

-- ── opportunities ────────────────────────────────────────────
DROP POLICY IF EXISTS "anon_select" ON opportunities;
DROP POLICY IF EXISTS "anon_insert" ON opportunities;
DROP POLICY IF EXISTS "anon_update" ON opportunities;
DROP POLICY IF EXISTS "anon_delete" ON opportunities;
DROP POLICY IF EXISTS "anon_all"    ON opportunities;

CREATE POLICY "auth_select" ON opportunities
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

CREATE POLICY "auth_insert" ON opportunities
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_update" ON opportunities
  FOR UPDATE TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_delete" ON opportunities
  FOR DELETE TO authenticated USING (auth.uid() IS NOT NULL);

-- ── attachments ──────────────────────────────────────────────
DROP POLICY IF EXISTS "anon_att_select" ON attachments;
DROP POLICY IF EXISTS "anon_att_insert" ON attachments;
DROP POLICY IF EXISTS "anon_att_delete" ON attachments;

CREATE POLICY "auth_att_select" ON attachments
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

CREATE POLICY "auth_att_insert" ON attachments
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_att_delete" ON attachments
  FOR DELETE TO authenticated USING (auth.uid() IS NOT NULL);

-- ── audit_trail ──────────────────────────────────────────────
DROP POLICY IF EXISTS "anon_audit_select" ON audit_trail;
DROP POLICY IF EXISTS "anon_audit_insert" ON audit_trail;
DROP POLICY IF EXISTS "anon_audit_delete" ON audit_trail;

CREATE POLICY "auth_audit_select" ON audit_trail
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

CREATE POLICY "auth_audit_insert" ON audit_trail
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_audit_delete" ON audit_trail
  FOR DELETE TO authenticated USING (auth.uid() IS NOT NULL);

-- ── user_settings ────────────────────────────────────────────
DROP POLICY IF EXISTS "anon_settings_select" ON user_settings;
DROP POLICY IF EXISTS "anon_settings_upsert" ON user_settings;
DROP POLICY IF EXISTS "anon_settings_update" ON user_settings;
DROP POLICY IF EXISTS "anon_settings_delete" ON user_settings;

CREATE POLICY "auth_settings_select" ON user_settings
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

CREATE POLICY "auth_settings_insert" ON user_settings
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_settings_update" ON user_settings
  FOR UPDATE TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_settings_delete" ON user_settings
  FOR DELETE TO authenticated USING (auth.uid() IS NOT NULL);

-- ── mileage_records ──────────────────────────────────────────
DROP POLICY IF EXISTS "anon_mile_select" ON mileage_records;
DROP POLICY IF EXISTS "anon_mile_insert" ON mileage_records;
DROP POLICY IF EXISTS "anon_mile_update" ON mileage_records;
DROP POLICY IF EXISTS "anon_mile_delete" ON mileage_records;

CREATE POLICY "auth_mile_select" ON mileage_records
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

CREATE POLICY "auth_mile_insert" ON mileage_records
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_mile_update" ON mileage_records
  FOR UPDATE TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_mile_delete" ON mileage_records
  FOR DELETE TO authenticated USING (auth.uid() IS NOT NULL);

-- ── post_delivery_records ────────────────────────────────────
DROP POLICY IF EXISTS "anon_post_select" ON post_delivery_records;
DROP POLICY IF EXISTS "anon_post_insert" ON post_delivery_records;
DROP POLICY IF EXISTS "anon_post_update" ON post_delivery_records;
DROP POLICY IF EXISTS "anon_post_delete" ON post_delivery_records;

CREATE POLICY "auth_post_select" ON post_delivery_records
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

CREATE POLICY "auth_post_insert" ON post_delivery_records
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_post_update" ON post_delivery_records
  FOR UPDATE TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "auth_post_delete" ON post_delivery_records
  FOR DELETE TO authenticated USING (auth.uid() IS NOT NULL);

-- ── storage.objects (lead-attachments bucket) ────────────────
DROP POLICY IF EXISTS "Attachments anon upload" ON storage.objects;
DROP POLICY IF EXISTS "Attachments anon read"   ON storage.objects;
DROP POLICY IF EXISTS "Attachments anon delete" ON storage.objects;

CREATE POLICY "Attachments auth upload" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'lead-attachments' AND auth.uid() IS NOT NULL);

CREATE POLICY "Attachments auth read" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'lead-attachments' AND auth.uid() IS NOT NULL);

CREATE POLICY "Attachments auth delete" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'lead-attachments' AND auth.uid() IS NOT NULL);

-- ── storage.objects (lead-avatars bucket) ────────────────────
DROP POLICY IF EXISTS "Avatars anon upload" ON storage.objects;
DROP POLICY IF EXISTS "Avatars anon read"   ON storage.objects;
DROP POLICY IF EXISTS "Avatars anon delete" ON storage.objects;

CREATE POLICY "Avatars auth upload" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'lead-avatars' AND auth.uid() IS NOT NULL);

CREATE POLICY "Avatars auth read" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'lead-avatars' AND auth.uid() IS NOT NULL);

CREATE POLICY "Avatars auth delete" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'lead-avatars' AND auth.uid() IS NOT NULL);
