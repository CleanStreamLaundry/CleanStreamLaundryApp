import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const inputs = [
  ['20260930130013_push_token_registration.sql', 'ec3075684bd75c87978ef0ed44b77f970d656b906c2c33ba95e037985010b657'],
  ['20261001011048_push_registration_bounds.sql', 'aab8796f25db121884c828adff41cb3c26fe00975b290894565287540d97ffea'],
];
const sha = value => createHash('sha256').update(value).digest('hex');
const bodies = inputs.map(([name, expected]) => {
  const source = readFileSync(new URL(`supabase/migrations/${name}`, root), 'utf8');
  assert.equal(sha(source), expected, name);
  assert.equal((source.match(/^begin;$/gmi) ?? []).length, 1);
  assert.equal((source.match(/^commit;$/gmi) ?? []).length, 1);
  return `-- SOURCE ${name} SHA256 ${expected}\n${source.replace(/^begin;$/mi, '').replace(/^commit;$/mi, '')}`;
});
const sql = `-- GENERATED two-source DEVELOPMENT push registration install only.
-- Target dnuuhupoxjtwqzaqylvb. Requires BOTH push tables absent, not a replay path.
-- Reuses installed admission/lifecycle; no sender, backfill, schedule or retention purge.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
${bodies.join('\n')}
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.request_account_deletion()', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.request_account_deletion()', 'EXECUTE')
    OR has_function_privilege('service_role', 'public.request_account_deletion()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Deletion containment drift; push install aborted' USING ERRCODE = '55000';
  END IF;
END;
$$;
COMMIT;
`;
const output = fileURLToPath(new URL('activation-push.sql', root));
writeFileSync(output, sql);
console.log(JSON.stringify({ output, sha256: sha(sql), sources: inputs.length }));
