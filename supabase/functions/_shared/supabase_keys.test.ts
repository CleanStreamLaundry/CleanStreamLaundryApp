import assert from "node:assert/strict";
import {
  callerPublishableKey,
  selectNamedSupabaseKey,
} from "./supabase_keys.ts";

const selected = "sb_publishable_synthetic_caller";
const other = "sb_publishable_synthetic_other";
const selector = "CLEANSTREAM_ADMIN_PUBLISHABLE_KEY_NAME";
const values = (): Record<string, string | undefined> => ({
  [selector]: "admin-component",
  SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
    "admin-component": selected,
    default: other,
  }),
  SUPABASE_ANON_KEY: "synthetic-legacy-public",
});

Deno.test("public keys: exact own selection with trusted kind", () => {
  assert.equal(
    selectNamedSupabaseKey(
      "admin-component",
      values().SUPABASE_PUBLISHABLE_KEYS,
      "publishable",
    ),
    selected,
  );
  assert.equal(
    selectNamedSupabaseKey(
      "default",
      values().SUPABASE_PUBLISHABLE_KEYS,
      "publishable",
    ),
    other,
  );
  assert.equal(
    selectNamedSupabaseKey(
      "admin-component",
      values().SUPABASE_PUBLISHABLE_KEYS,
      "secret",
    ),
    null,
  );
});

for (
  const name of [
    "",
    " ",
    " admin-component",
    "admin-component\n",
    "absent",
    "toString",
    "admin\u0000component",
    "admin\u007fcomponent",
  ]
) {
  Deno.test(`public keys: invalid selector ${JSON.stringify(name)} fails closed`, () => {
    const config: Record<string, string | undefined> = {
      ...values(),
      [selector]: name,
    };
    assert.throws(() => callerPublishableKey((key) => config[key], selector));
    if (name.includes("\u0000") || name.includes("\u007f")) {
      assert.equal(
        selectNamedSupabaseKey(
          name,
          JSON.stringify({ [name]: selected }),
          "publishable",
        ),
        null,
      );
    }
  });
}

for (
  const serialized of [
    undefined,
    "{broken",
    "null",
    "[]",
    '"string"',
    "42",
    JSON.stringify({ default: selected }),
    JSON.stringify({ "admin-component": null }),
    JSON.stringify({ "admin-component": 123 }),
    JSON.stringify({ "admin-component": { key: selected } }),
    JSON.stringify({ "admin-component": "sb_secret_synthetic" }),
    JSON.stringify({ "admin-component": "synthetic-legacy-public" }),
    JSON.stringify({ "admin-component": "sb_publishable_" }),
    JSON.stringify({ "admin-component": `${selected}\n` }),
    JSON.stringify({ "admin-component": ` ${selected}` }),
  ]
) {
  Deno.test("public keys: bad dictionary fails without reading legacy or secrets", () => {
    const config: Record<string, string | undefined> = {
      ...values(),
      SUPABASE_PUBLISHABLE_KEYS: serialized,
    };
    const reads: string[] = [];
    assert.throws(() =>
      callerPublishableKey((key) => {
        reads.push(key);
        return config[key];
      }, selector), { message: "Public key configuration unavailable" });
    assert.deepEqual(reads, [selector, "SUPABASE_PUBLISHABLE_KEYS"]);
  });
}

Deno.test("public keys: absent selector preserves legacy without dictionary lookup", () => {
  const config = values();
  delete config[selector];
  const reads: string[] = [];
  assert.equal(
    callerPublishableKey((key) => {
      reads.push(key);
      return config[key];
    }, selector),
    config.SUPABASE_ANON_KEY,
  );
  assert.deepEqual(reads, [selector, "SUPABASE_ANON_KEY"]);
});

Deno.test("public keys: component names are independent and removal needs explicit rollback", () => {
  const account = "CLEANSTREAM_ACCOUNT_PUBLISHABLE_KEY_NAME";
  const config: Record<string, string | undefined> = {
    ...values(),
    [account]: "default",
  };
  const env = (key: string) => config[key];
  assert.equal(callerPublishableKey(env, selector), selected);
  assert.equal(callerPublishableKey(env, account), other);
  config.SUPABASE_PUBLISHABLE_KEYS = JSON.stringify({ default: other });
  assert.throws(() => callerPublishableKey(env, selector));
  assert.equal(callerPublishableKey(env, account), other);
  delete config[selector];
  assert.equal(callerPublishableKey(env, selector), config.SUPABASE_ANON_KEY);
});
