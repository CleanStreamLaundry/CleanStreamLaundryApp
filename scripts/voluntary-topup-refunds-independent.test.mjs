import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  blocked,
  disposableCluster,
} from "./test-support/policy-admission-pg.mjs";

const read = (p) => readFile(new URL(p, import.meta.url), "utf8");
const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const user = uid(1),
  owner = uid(2),
  sid = uid(11),
  osid = uid(12),
  factor = uid(20);
const claims = (who = user, extra = {}) => ({
  sub: who,
  session_id: who === owner ? osid : sid,
  role: "authenticated",
  aal: who === owner ? "aal2" : "aal1",
  exp: Math.floor(Date.now() / 1000) + 3600,
  ...extra,
});
const context = (who = user, extra = {}) =>
  `set local request.jwt.claims='${JSON.stringify(claims(who, extra))}';
  set local request.jwt.claim.sub=''; set local role authenticated;`;
const asUser = (sql, who = user, extra = {}) =>
  `begin; ${context(who, extra)} ${sql}; commit;`;
const wallet =
  `(select id from public.wallet_accounts where user_id='${user}')`;

test("independent refund QA with newsletter and lifecycle migrations", {
  timeout: 180000,
}, async (t) => {
  const cluster = await disposableCluster(t, process.env.PG_BIN),
    db = await cluster.connect();
  const run = async (sql) => {
    const c = await cluster.connect();
    try {
      return await c.query(sql);
    } finally {
      await c.close();
    }
  };
  const call = async (sql, who = user, extra = {}) =>
    JSON.parse(await run(asUser(sql, who, extra)));
  const fixture =
    (await read("../supabase/tests/wallet_financial_locking.fixture.sql"))
      .split("-- AFTER_BASELINE_MIGRATIONS");
  await db.query("create role postgres superuser; set role postgres;");
  await db.query(fixture[0]);
  for (
    const file of [
      "20260526010000_wallet_ledger_compliance.sql",
      "20260803150427_cortina_qr_remote_vend.sql",
      "20260807191723_harden_refund_resolution.sql",
      "20260929231120_serialize_wallet_financial_writes.sql",
    ]
  ) {
    await db.query(await read(`../supabase/migrations/${file}`));
  }
  await db.query(fixture[1]);
  await db.query(
    `alter table auth.users add column email_confirmed_at timestamptz,
    add column is_anonymous boolean default false, add column banned_until timestamptz,
    add column deleted_at timestamptz, add column raw_user_meta_data jsonb default '{}',
    add column raw_app_meta_data jsonb default '{}', add column created_at timestamptz default now();
    alter table public.profiles add column created_at timestamptz default now();
    alter table public."Location_to_Admin" enable row level security;`,
  );
  for (
    const file of [
      "20260929223124_protect_profile_authority.sql",
      "20260929234955_loyalty_policy_acceptance.sql",
    ]
  ) {
    await db.query(await read(`../supabase/migrations/${file}`));
  }
  await db.query(await read("../supabase/tests/account_admission.fixture.sql"));
  for (
    const file of [
      "20260930005456_account_admission.sql",
      "20260930013417_enforce_profile_terms_admission.sql",
      "20260930024142_protect_location_membership.sql",
      "20260930063923_recoverable_account_deletion.sql",
      "20260930125527_newsletter_consent_mail_outbox.sql",
      "20260930125554_voluntary_topup_refunds.sql",
    ]
  ) {
    await db.query(await read(`../supabase/migrations/${file}`));
  }
  const reset = () =>
    db.query(
      `truncate private.mail_webhook_event,private.mail_outbox,private.newsletter_consent,private.mail_suppression;
    update private.mail_settings set enabled=false;
    truncate auth.users cascade;
    insert into auth.users(id,email,email_confirmed_at) values
      ('${user}','member@example.test',now()),('${owner}','owner@example.test',now());
    insert into public.profiles(id,roles) values('${user}','User'),('${owner}','Owner');
    insert into auth.sessions(id,user_id,aal,created_at,factor_id) values
      ('${sid}','${user}','aal1',now()-interval '1 hour',null),('${osid}','${owner}','aal2',now(),'${factor}');
    insert into auth.mfa_factors(id,user_id,factor_type,status) values('${factor}','${owner}','totp','verified');
    insert into public."Locations" values(1),(2) on conflict do nothing;
    insert into public."Machines"(id,"Location_ID") values(1,1) on conflict do nothing;
    insert into public."Location_to_Admin" values('${owner}',1);
    update private.topup_refund_policy set enabled_at=now()-interval '3 days';
    update private.mail_settings set enabled=true,rollout_at=now()-interval '1 hour';`,
    );
  let count = 0;
  const load = async (amount = 2000, location = "null") => {
    const key = `qa_${++count}`;
    await db.query(
      `select public.record_wallet_load_from_stripe('${user}',${amount},'pi_${key}');
      select public.record_topup_refund_provenance('pi_${key}','${user}',${amount},clock_timestamp()-interval '1 minute','evt_${key}',false,${location});`,
    );
    return Number(
      await db.query(
        `select id from public.wallet_loads where stripe_payment_intent_id='pi_${key}';`,
      ),
    );
  };
  const request = (id) =>
    call(`select public.request_voluntary_topup_refund(${id})`);
  const review = (id, action = "approve") =>
    call(
      `select public.review_voluntary_topup_refund('${id}','${action}')`,
      owner,
    );
  const prep = async (id) =>
    JSON.parse(
      await db.query(`select public.prepare_voluntary_topup_refund('${id}');`),
    );
  const settle = async (
    r,
    op,
    status = "succeeded",
    currency = "usd",
    mode = "false",
    provider = `re_${r.load_id}`,
  ) =>
    JSON.parse(
      await run(
        `select public.reconcile_voluntary_topup_refund('${r.id}','${provider}','${status}',
      '${op.intent}',${r.principal_cents},'${currency}',${mode});`,
      ),
    );
  const balance = async () =>
    JSON.parse(
      await db.query(
        `select json_build_array(paid_balance_cents,promo_balance_cents,
    (select round(reward_tracker*100) from public.profiles where id='${user}')) from public.wallet_balances where wallet_account_id=${wallet};`,
      ),
    );
  const fresh = (name, fn) =>
    t.test(name, async () => {
      await reset();
      await fn();
    });
  const confirmNewsletter = async () => {
    await call(
      "select public.newsletter_request(true,'newsletter-v1','settings')",
    );
    const o = JSON.parse(await db.query("select public.mail_claim();"));
    assert.equal(
      await db.query(
        `select public.mail_prepare('${o.id}','${o.lease_id}','${
          "a".repeat(64)
        }','${"b".repeat(64)}','${"c".repeat(64)}');`,
      ),
      "t",
    );
    await db.query(
      `select public.newsletter_token('confirm','${"b".repeat(64)}');`,
    );
    return JSON.parse(await db.query("select public.mail_claim();"));
  };

  for (
    const [name, mutation] of [
      [
        "Owner role revoked",
        `update public.profiles set roles='User' where id='${owner}'`,
      ],
      ["Owner session deleted", `delete from auth.sessions where id='${osid}'`],
      [
        "Owner session expired",
        `update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='${osid}'`,
      ],
      [
        "Owner TOTP revoked",
        `update auth.mfa_factors set status='unverified' where id='${factor}'`,
      ],
      [
        "Owner location removed",
        `delete from public."Location_to_Admin" where user_id='${owner}'`,
      ],
    ]
  ) {
    await fresh(`${name} during wallet wait cannot approve`, async () => {
      const r = await request(await load(2000, "1")),
        a = await cluster.connect(),
        b = await cluster.connect();
      try {
        await a.query(
          `begin; select id from public.wallet_accounts where id=${wallet} for no key update;`,
        );
        const waiting = b.query(
          asUser(
            `select public.review_voluntary_topup_refund('${r.id}','approve')`,
            owner,
          ),
        );
        const rejection = assert.rejects(
          waiting,
          /owner_required|session_invalid|location_forbidden/,
        );
        await blocked(db, b, a);
        await db.query(`${mutation};`);
        await a.query("commit;");
        await rejection;
        assert.equal(
          await db.query(
            `select status from private.voluntary_topup_refunds where id='${r.id}';`,
          ),
          "requested",
        );
        assert.deepEqual(await balance(), [0, 0, 0]);
      } finally {
        await a.close();
        await b.close();
      }
    });
  }
  await fresh(
    "customer session deleted during wallet wait cannot reserve",
    async () => {
      const id = await load(),
        a = await cluster.connect(),
        b = await cluster.connect();
      try {
        await a.query(
          `begin; select id from public.wallet_accounts where id=${wallet} for no key update;`,
        );
        const waiting = b.query(
          asUser(`select public.request_voluntary_topup_refund(${id})`),
        );
        const rejection = assert.rejects(waiting, /session_invalid/);
        await blocked(db, b, a);
        await db.query(`delete from auth.sessions where id='${sid}';`);
        await a.query("commit;");
        await rejection;
        assert.deepEqual(await balance(), [2000, 500, 0]);
      } finally {
        await a.close();
        await b.close();
      }
    },
  );
  for (
    const [currency, mode, provider] of [
      ["eur", "false", "re_x"],
      ["usd", "true", "re_x"],
      ["usd", "null", "re_x"],
      ["usd", "false", "wrong"],
    ]
  ) {
    await fresh(
      `settlement rejects ${currency}/${mode}/${provider}`,
      async () => {
        const r = await request(await load());
        await review(r.id);
        const op = await prep(r.id);
        await assert.rejects(
          settle(r, op, "succeeded", currency, mode, provider),
          /provider_mismatch/,
        );
        assert.deepEqual(await balance(), [0, 0, 0]);
        assert.equal(
          await db.query(
            `select status from private.voluntary_topup_refunds where id='${r.id}';`,
          ),
          "unknown",
        );
      },
    );
  }
  await fresh(
    "concurrent prepare uses one dispatch clock and idempotency key",
    async () => {
      const r = await request(await load());
      await review(r.id);
      const a = await cluster.connect(), b = await cluster.connect();
      try {
        const first = JSON.parse(
          await a.query(
            `begin; select public.prepare_voluntary_topup_refund('${r.id}');`,
          ),
        );
        const waiting = b.query(
          `select public.prepare_voluntary_topup_refund('${r.id}');`,
        );
        await blocked(db, b, a);
        await a.query("commit;");
        assert.deepEqual(JSON.parse(await waiting), first);
        assert.deepEqual(await balance(), [0, 0, 0]);
      } finally {
        await a.close();
        await b.close();
      }
    },
  );
  for (const order of [[0, 1, 2], [2, 0, 1], [1, 2, 0]]) {
    await fresh(`reward unwind order ${order}`, async () => {
      const amounts = [1500, 1000, 2500], ids = [];
      for (const amount of amounts) {
        ids.push(await load(amount));
      }
      const operations = [];
      let total = 5000;
      for (const i of order) {
        operations.push(await request(ids[i]));
        total -= amounts[i];
        assert.deepEqual(await balance(), [
          total,
          Math.floor(total / 2000) * 500,
          total % 2000,
        ]);
      }
      for (const r of operations.reverse()) {
        await review(r.id, "deny");
        total += r.principal_cents;
        assert.deepEqual(await balance(), [
          total,
          Math.floor(total / 2000) * 500,
          total % 2000,
        ]);
        await review(r.id, "deny");
        assert.deepEqual(await balance(), [
          total,
          Math.floor(total / 2000) * 500,
          total % 2000,
        ]);
      }
    });
  }
  for (const status of ["succeeded", "failed", "canceled"]) {
    await fresh(
      `deletion suppresses newsletter while provider ${status} settles independently`,
      async () => {
        const mail = await confirmNewsletter(), r = await request(await load());
        await review(r.id);
        const op = await prep(r.id);
        await call("select public.request_account_deletion()");
        assert.equal(
          await db.query(
            `select public.mail_prepare('${mail.id}','${mail.lease_id}','${
              "a".repeat(64)
            }',null,'${"c".repeat(64)}');`,
          ),
          "f",
        );
        assert.equal((await settle(r, op, status)).status, status);
        await settle(r, op, status);
        assert.deepEqual(
          await balance(),
          status === "succeeded" ? [0, 0, 0] : [2000, 500, 0],
        );
        assert.equal(
          await call("select to_json(private.account_access_allowed())"),
          false,
        );
        assert.equal(
          await db.query(
            "select count(*) from private.newsletter_consent where unsubscribed_at is null;",
          ),
          "0",
        );
        assert.equal(
          await db.query(
            "select count(*) from private.mail_outbox where state in ('ready','leased','sending');",
          ),
          "0",
        );
        await db.query(
          `insert into auth.sessions(id,user_id,aal,created_at) values('${
            uid(99)
          }','${user}','aal1',clock_timestamp());`,
        );
        await call("select public.restore_account()", user, {
          session_id: uid(99),
        });
        assert.equal(
          await db.query(
            "select count(*) from private.newsletter_consent where unsubscribed_at is null;",
          ),
          "0",
        );
        assert.equal(
          await db.query(
            "select count(*) from private.mail_outbox where kind='account_welcome';",
          ),
          "0",
        );
        await assert.rejects(
          call("select public.list_voluntary_topup_refunds()"),
          /session_invalid/,
        );
        assert.equal(
          (await call("select public.list_voluntary_topup_refunds()", user, {
            session_id: uid(99),
          })).length,
          1,
        );
      },
    );
  }
  await fresh(
    "pending-deletion refund exception and new funding do not reenable marketing",
    async () => {
      await confirmNewsletter();
      await call("select public.request_account_deletion()");
      const id = await load();
      const r = await request(id);
      await review(r.id);
      const op = await prep(r.id);
      await settle(r, op);
      assert.deepEqual(await balance(), [0, 0, 0]);
      assert.equal(
        await db.query(
          "select count(*) from private.mail_outbox where state in ('ready','leased','sending');",
        ),
        "0",
      );
    },
  );
  for (const status of ["failed", "canceled"]) {
    await fresh(
      `bound pending refund becoming ${status} releases principal and rewards`,
      async () => {
        const r = await request(await load());
        await review(r.id);
        const first = await prep(r.id);
        await settle(r, first, "pending");
        const bound = await prep(r.id);
        assert.equal(bound.refund_id, `re_${r.load_id}`);
        assert.deepEqual(await balance(), [0, 0, 0]);
        await settle(r, bound, status);
        assert.deepEqual(await balance(), [2000, 500, 0]);
        await settle(r, bound, status);
        assert.deepEqual(await balance(), [2000, 500, 0]);
      },
    );
  }
  await fresh(
    "deletion profile lock aborts failed-refund release safely; retry credits once",
    async () => {
      const r = await request(await load());
      await review(r.id);
      const op = await prep(r.id);
      const a = await cluster.connect();
      try {
        await a.query(
          `begin; ${context()} select public.request_account_deletion();`,
        );
        await assert.rejects(settle(r, op, "failed"), /could not obtain lock/);
        assert.deepEqual(await balance(), [0, 0, 0]);
        await a.query("commit;");
        await settle(r, op, "failed");
        await settle(r, op, "failed");
        assert.deepEqual(await balance(), [2000, 500, 0]);
      } finally {
        await a.close();
      }
    },
  );
  await fresh(
    "combined grants keep provider callbacks service-only and private tables inaccessible",
    async () => {
      for (
        const sql of [
          "select public.mail_claim()",
          "select * from private.mail_outbox",
          "select * from private.voluntary_topup_refunds",
          "select public.prepare_voluntary_topup_refund('00000000-0000-4000-8000-000000000001')",
        ]
      ) {
        await assert.rejects(run(asUser(sql)), /permission denied/);
      }
      assert.equal(
        await db.query(
          `select has_function_privilege('service_role','public.record_wallet_load_from_stripe(uuid,integer,text,text,text,text)','EXECUTE');`,
        ),
        "t",
      );
      assert.equal(
        await db.query(
          `select has_function_privilege('authenticated','public.record_wallet_load_from_stripe(uuid,integer,text,text,text,text)','EXECUTE');`,
        ),
        "f",
      );
    },
  );
});
