-- Configuration/catalog only. Composer runs after separately coordinated install.
-- No object/report/customer rows, provider calls or mutation.
SELECT jsonb_build_object(
  'functions', (SELECT jsonb_agg(jsonb_build_object(
    'signature', signature, 'exists', to_regprocedure(signature) IS NOT NULL,
    'authenticated_execute', CASE WHEN to_regprocedure(signature) IS NOT NULL
      THEN has_function_privilege('authenticated', signature, 'EXECUTE') END,
    'anon_execute', CASE WHEN to_regprocedure(signature) IS NOT NULL
      THEN has_function_privilege('anon', signature, 'EXECUTE') END,
    'service_execute', CASE WHEN to_regprocedure(signature) IS NOT NULL
      THEN has_function_privilege('service_role', signature, 'EXECUTE') END
  )) FROM unnest(ARRAY[
    'public.get_maintenance_attachment(text)',
    'private.maintenance_attachment_allowed(uuid)',
    'private.maintenance_upload_allowed(text,text,timestamp with time zone,boolean)'
  ]) signature),
  'storage_table', (SELECT jsonb_build_object(
    'owner', pg_get_userbyid(relowner), 'rls', relrowsecurity
  ) FROM pg_class WHERE oid = 'storage.objects'::regclass),
  'policies', (SELECT jsonb_agg(jsonb_build_object(
    'name', policyname, 'mode', permissive, 'roles', roles, 'command', cmd,
    'using', qual, 'check', with_check
  ) ORDER BY policyname) FROM pg_policies WHERE schemaname = 'storage'
    AND tablename = 'objects' AND policyname IN (
      'maintenance_attachment_read_scope', 'maintenance_attachment_read',
      'maintenance_attachment_upload_scope', 'maintenance_attachment_no_update',
      'maintenance_attachment_no_delete'
    )),
  'bucket_configuration', (SELECT jsonb_build_object(
    'id', id, 'public', public, 'file_size_limit', file_size_limit,
    'allowed_mime_types', allowed_mime_types
  ) FROM storage.buckets WHERE id = 'maintenance-images'),
  'deletion_held', NOT (
    has_function_privilege('anon', 'public.request_account_deletion()', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.request_account_deletion()', 'EXECUTE')
    OR has_function_privilege('service_role', 'public.request_account_deletion()', 'EXECUTE')
  )
);
