import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildPlan, parseArguments, readReleaseConfiguration } from './build_mobile_release.mjs';

const fixture = () => ({ channel: 'play-internal', buildNumber: '9',
  client: { SUPABASE_URL: 'https://dnuuhupoxjtwqzaqylvb.supabase.co', ANON_KEY: 'sb_publishable_fixture', STRIPE_PUBLISHABLE_KEY: 'pk_test_fixture' },
  firebase: { FIREBASE_ENV: 'dev', FIREBASE_ANDROID_API_KEY: 'fixture', FIREBASE_IOS_API_KEY: 'fixture' } });

for (const channel of ['testflight', 'play-internal']) {
  test(`${channel} selects test payments and dev Firebase in release mode`, () => {
    const input = { ...fixture(), channel };
    const plan = buildPlan(input);
    assert.equal(plan.paymentEnvironment, 'test');
    assert.equal(plan.firebaseEnvironment, 'dev');
    assert.ok(plan.commands[0].includes('--release'));
    assert.ok(plan.commands[0].includes('--build-number=9'));
    assert.ok(plan.commands[0].some(arg => arg.includes('/dev/')));
    assert.ok(plan.commands[0].includes('--dart-define-from-file=config/client/test.defines.json'));
    assert.ok(plan.commands[0].includes(`--dart-define=CLIENT_CHANNEL=${channel}`));
    assert.ok(!JSON.stringify(plan).includes(input.client.STRIPE_PUBLISHABLE_KEY));
    if (channel === 'testflight') assert.equal(plan.commands[1].at(-1), 'archive');
  });
  test(`${channel} rejects live Stripe`, () => {
    const input = { ...fixture(), channel }; input.client.STRIPE_PUBLISHABLE_KEY = 'pk_live_fixture';
    assert.throws(() => buildPlan(input), /Stripe test/);
  });
}
for (const name of ['PAYMENT_ENV', 'STRIPE_ENV', 'CORTINA_ENV']) {
  test(`beta rejects conflicting ${name}`, () => assert.throws(() => buildPlan({ ...fixture(), environment: { [name]: 'production' } }), /conflicts/));
}
test('beta rejects a different backend', () => {
  const input = fixture(); input.client.SUPABASE_URL = 'https://other.supabase.co';
  assert.throws(() => buildPlan(input), /backend/);
});
test('beta rejects production Firebase', () => {
  const input = fixture(); input.firebase.FIREBASE_ENV = 'prod';
  assert.throws(() => buildPlan(input), /Firebase dev/);
});
test('bundled privileged settings and service-role JWT are refused', () => {
  const input = fixture(); input.client.STRIPE_SECRET_KEY = 'synthetic';
  assert.throws(() => buildPlan(input), /only the three/);
  delete input.client.STRIPE_SECRET_KEY;
  input.client.ANON_KEY = `header.${Buffer.from(JSON.stringify({ role: 'service_role' })).toString('base64url')}.signature`;
  assert.throws(() => buildPlan(input), /public/);
});
test('legacy anon key remains compatible', () => {
  const input = fixture(); input.client.ANON_KEY = `header.${Buffer.from(JSON.stringify({ role: 'anon' })).toString('base64url')}.signature`;
  assert.equal(buildPlan(input).paymentEnvironment, 'test');
});
for (const channel of ['production-ios', 'production-android']) {
  test(`${channel} requires complete explicit live setup`, () => {
    const input = { ...fixture(), channel };
    assert.throws(() => buildPlan(input), /Stripe live/);
    input.client.STRIPE_PUBLISHABLE_KEY = 'pk_live_fixture';
    assert.throws(() => buildPlan(input), /production-config/);
    input.production = { paymentEnvironment: 'live', supabaseUrl: 'https://production.supabase.co' };
    assert.throws(() => buildPlan(input), /backend/);
    input.client.SUPABASE_URL = input.production.supabaseUrl;
    assert.throws(() => buildPlan(input), /Firebase prod/);
    input.firebase.FIREBASE_ENV = 'prod';
    input.clientConfigPath = '/synthetic/production.defines.json';
    assert.equal(buildPlan(input).paymentEnvironment, 'live');
    assert.throws(() => buildPlan({ ...input, environment: { PAYMENT_ENV: 'test' } }), /conflicts/);
  });
}
test('channel and store build number cannot silently default', () => {
  for (const buildNumber of [undefined, '0', '-1', '9 --dart-define=x']) assert.throws(() => buildPlan({ ...fixture(), buildNumber }), /build-number/);
  assert.throws(() => buildPlan({ ...fixture(), channel: undefined }), /Choose/);
});

function configurationFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'cleanstream-client-config-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'config/client'), { recursive: true });
  for (const mode of ['dev', 'prod']) {
    mkdirSync(join(root, `config/firebase/${mode}`), { recursive: true });
    for (const platform of ['ios', 'android']) writeFileSync(join(root, `config/firebase/${mode}/${platform}.defines.json`), JSON.stringify({ ...fixture().firebase, FIREBASE_ENV: mode }));
  }
  writeFileSync(join(root, 'config/client/test.defines.json'), JSON.stringify(fixture().client));
  writeFileSync(join(root, '.env'), 'SUPABASE_URL=https://local.supabase.co\nANON_KEY=sb_publishable_local\nSTRIPE_PUBLISHABLE_KEY=pk_live_local_never_selected\n');
  return root;
}
for (const channel of ['testflight', 'play-internal']) {
  test(`${channel} selects saved beta settings even when local .env is live`, t => {
    const root = configurationFixture(t);
    const before = readFileSync(join(root, '.env'), 'utf8');
    const input = readReleaseConfiguration({ channel, 'build-number': '9' }, root);
    assert.deepEqual(input.client, fixture().client);
    const plan = buildPlan(input);
    assert.equal(plan.paymentEnvironment, 'test');
    assert.equal(readFileSync(join(root, '.env'), 'utf8'), before);
    assert.ok(!JSON.stringify(plan).includes(input.client.ANON_KEY));
    assert.throws(() => readReleaseConfiguration({ channel, 'production-config': '/synthetic/live.json' }, root), /always select/);
  });
}
test('explicit production config selects complete public values without .env', t => {
  const root = configurationFixture(t);
  const file = join(root, 'config/client/production.defines.json');
  const production = { ...fixture().client, STRIPE_PUBLISHABLE_KEY: 'pk_live_synthetic',
    SUPABASE_URL: 'https://production.supabase.co', supabaseUrl: 'https://production.supabase.co', paymentEnvironment: 'live' };
  writeFileSync(file, JSON.stringify(production));
  const input = readReleaseConfiguration({ channel: 'production-ios', 'build-number': '9', 'production-config': file }, root);
  const plan = buildPlan(input);
  assert.equal(plan.paymentEnvironment, 'live');
  assert.ok(plan.commands[0].includes(`--dart-define-from-file=${file}`));
  assert.ok(plan.commands[0].includes('--dart-define=CLIENT_CHANNEL=production-ios'));
});
test('selected files reject missing or privileged public fields', t => {
  const root = configurationFixture(t);
  const file = join(root, 'config/client/test.defines.json');
  for (const config of [{}, { ...fixture().client, STRIPE_SECRET_KEY: 'synthetic' },
    { ...fixture().client, CLIENT_CHANNEL: 'production-ios' }]) {
    writeFileSync(file, JSON.stringify(config));
    assert.throws(() => readReleaseConfiguration({ channel: 'testflight', 'build-number': '9' }, root), /public|unsupported/);
  }
  rmSync(file);
  assert.throws(() => readReleaseConfiguration({ channel: 'testflight', 'build-number': '9' }, root), /ENOENT/);
});
test('unused bundled .env cannot introduce privileged keys into the artifact', t => {
  const root = configurationFixture(t);
  writeFileSync(join(root, '.env'), 'ANON_KEY=sb_secret_synthetic\nSTRIPE_PUBLISHABLE_KEY=pk_live_synthetic\n');
  assert.throws(() => readReleaseConfiguration({ channel: 'testflight', 'build-number': '9' }, root), /public/);
});
test('CLI refuses flags that could override validated configuration', () => {
  assert.deepEqual(parseArguments(['--channel', 'testflight', '--build-number', '9', '--check']), { channel: 'testflight', 'build-number': '9', check: true });
  for (const args of [['--dart-define=FIREBASE_ENV=prod'], ['--channel'], ['--channel', 'testflight', '--channel', 'production-ios']]) assert.throws(() => parseArguments(args), /Extra Flutter overrides/);
});
