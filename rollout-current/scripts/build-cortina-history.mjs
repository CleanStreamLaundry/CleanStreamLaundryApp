import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const active = '/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp';
const sha = (text) => createHash('sha256').update(text).digest('hex');
const artifactHash = '4837e95074c0de61ef9a97f13131b3b247f093ea05d3d7e7815783e1a8cb6990';
assert.equal(sha(readFileSync(resolve(root, 'cortina-prerequisites.sql'))), artifactHash);
const manifest = readFileSync(resolve(root, 'migration-sources.sha256'), 'utf8');
assert.equal(sha(manifest), '91dcfe3fabf41012cc73874724f6cf8ada99afdab08000d7298515592561d822');
const inputs = manifest.trimEnd().split('\n').map((line) => {
  const match = /^([a-f0-9]{64})  (.+)$/.exec(line);
  assert.ok(match);
  const [, hash, path] = match;
  const source = readFileSync(resolve(active, path), 'utf8');
  assert.equal(sha(source), hash, path);
  const filename = basename(path);
  const identity = /^(\d{14})_([a-z0-9_]+)\.sql$/.exec(filename);
  assert.ok(identity, filename);
  assert.ok(!source.includes('$cortina_source$') && !source.includes('$cortina_history$'));
  return { version: identity[1], name: identity[2], hash, source };
});
assert.equal(inputs.length, 4);
assert.equal(new Set(inputs.map((input) => input.version)).size, 4);
const values = inputs.map(({ version, name, hash, source }) =>
  `    ('${version}', '${name}', '${hash}', $cortina_source$${source}$cortina_source$)`
).join(',\n');
const versions = inputs.map(({ version }) => `'${version}'`).join(', ');

const sql = `-- Mechanical four-source assembly; reproducible by scripts/build-cortina-history.mjs.
-- Metadata only, NEVER executes stored SQL. DEVELOPMENT dnuuhupoxjtwqzaqylvb.
-- Run only AFTER successful exact four-SQL installation and accepted metadata postflight.
-- Installation artifact ${artifactHash}; C/D is already separately recorded.
-- No target-history absence is assumed: abort on any collision, never overwrite.
-- Each statements array contains ONE verbatim reviewed source file as inert text.
-- Original outer wrappers are history text only; installation used one outer transaction.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE;

DO $cortina_history$
DECLARE
  entry record;
  inserted_count integer := 0;
BEGIN
  IF (SELECT count(*) FROM pg_catalog.pg_attribute
      WHERE attrelid = 'supabase_migrations.schema_migrations'::regclass
        AND NOT attisdropped
        AND ((attname IN ('version', 'name') AND atttypid = 'text'::regtype)
          OR (attname = 'statements' AND atttypid = 'text[]'::regtype))) <> 3
    OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_attribute a
        ON a.attrelid = i.indrelid AND a.attname = 'version'
      WHERE i.indrelid = 'supabase_migrations.schema_migrations'::regclass
        AND i.indisunique AND i.indisvalid AND i.indnkeyatts = 1
        AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indkey[0] = a.attnum
    ) THEN
    RAISE EXCEPTION 'Unexpected migration history shape or missing unique version index';
  END IF;

  FOR entry IN SELECT * FROM (VALUES
${values}
  ) AS approved(version, name, source_sha256, source_sql)
  LOOP
    IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations h
               WHERE h.version = entry.version) THEN
      RAISE EXCEPTION 'History version % already exists; entire transaction aborted', entry.version;
    END IF;
    IF encode(sha256(convert_to(entry.source_sql, 'UTF8')), 'hex') <> entry.source_sha256 THEN
      RAISE EXCEPTION 'History source digest mismatch for %', entry.version;
    END IF;
    INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
      VALUES (entry.version, entry.name, ARRAY[entry.source_sql]::text[]);
    inserted_count := inserted_count + 1;
  END LOOP;
  IF inserted_count <> 4 THEN
    RAISE EXCEPTION 'Expected exactly 4 history entries';
  END IF;
END;
$cortina_history$;
COMMIT;

-- Receipt reads only these history metadata rows, never customer records.
SELECT version, name, cardinality(statements) AS stored_source_files,
       encode(sha256(convert_to(statements[1], 'UTF8')), 'hex') AS source_sha256
FROM supabase_migrations.schema_migrations
WHERE version IN (${versions})
ORDER BY version;
`;
const output = resolve(root, 'record-cortina-history.sql');
writeFileSync(output, sql);
console.log(JSON.stringify({ output, sha256: sha(sql), versions: inputs.length }));
