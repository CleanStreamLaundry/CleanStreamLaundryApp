-- Metadata only: use before install and for postflight. No push/user/token rows.
SELECT jsonb_build_object(
  'prerequisites', jsonb_build_object(
    'admission', to_regprocedure('public.get_admission_status()') IS NOT NULL,
    'account_access', to_regprocedure('private.account_access_allowed()') IS NOT NULL,
    'lifecycle', to_regclass('private.account_lifecycle') IS NOT NULL),
  'tables', (SELECT jsonb_agg(jsonb_build_object(
    'table', c.relname, 'rls', c.relrowsecurity, 'owner', pg_get_userbyid(c.relowner)
  ) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='private' AND c.relname IN ('push_installations','push_creation_budget')),
  'functions', (SELECT jsonb_agg(jsonb_build_object(
    'signature', signature, 'exists', to_regprocedure(signature) IS NOT NULL,
    'anon', CASE WHEN to_regprocedure(signature) IS NOT NULL THEN has_function_privilege('anon', signature, 'EXECUTE') END,
    'authenticated', CASE WHEN to_regprocedure(signature) IS NOT NULL THEN has_function_privilege('authenticated', signature, 'EXECUTE') END,
    'service', CASE WHEN to_regprocedure(signature) IS NOT NULL THEN has_function_privilege('service_role', signature, 'EXECUTE') END
  )) FROM unnest(ARRAY['public.prepare_push_installation(uuid,uuid)',
    'public.register_push_token(uuid,uuid,text,text,text)',
    'public.revoke_push_installation(uuid,uuid)']) signature),
  'indexes', (SELECT jsonb_agg(indexdef ORDER BY indexname) FROM pg_indexes
    WHERE schemaname='private' AND tablename IN ('push_installations','push_creation_budget')),
  'cleanup_fk', (SELECT jsonb_agg(pg_get_constraintdef(oid)) FROM pg_constraint
    WHERE conrelid=to_regclass('private.push_installations') AND contype='f'
      AND pg_get_constraintdef(oid) LIKE '%cleanup_session_id%'),
  'lifecycle_trigger', (SELECT tgenabled FROM pg_trigger
    WHERE tgrelid='private.account_lifecycle'::regclass AND tgname='revoke_lifecycle_push'),
  'history', (SELECT jsonb_agg(version ORDER BY version) FROM supabase_migrations.schema_migrations
    WHERE version IN ('20260930130013','20261001011048')),
  'deletion_held', NOT (
    has_function_privilege('anon','public.request_account_deletion()','EXECUTE')
    OR has_function_privilege('authenticated','public.request_account_deletion()','EXECUTE')
    OR has_function_privilege('service_role','public.request_account_deletion()','EXECUTE'))
);
