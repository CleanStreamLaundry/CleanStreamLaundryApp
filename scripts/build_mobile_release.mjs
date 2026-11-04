import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const channels = {
  testflight: ['ios', 'test'],
  'play-internal': ['android', 'test'],
  'production-ios': ['ios', 'live'],
  'production-android': ['android', 'live'],
};
const betaBackend = 'https://dnuuhupoxjtwqzaqylvb.supabase.co';
const publicFields = ['SUPABASE_URL', 'ANON_KEY', 'STRIPE_PUBLISHABLE_KEY'];

function validatePublicClient(client, mode) {
  const allowed = new Set(publicFields);
  if (Object.keys(client).some(key => !allowed.has(key))) throw new Error('Client configuration must contain only the three public client settings.');
  if (!new RegExp(`^pk_${mode}_[A-Za-z0-9_]+$`).test(client.STRIPE_PUBLISHABLE_KEY ?? '') || /replace|placeholder/i.test(client.STRIPE_PUBLISHABLE_KEY)) {
    throw new Error(`Channel requires a configured Stripe ${mode} publishable key.`);
  }
  const publicKey = client.ANON_KEY ?? '';
  let legacyAnon = false;
  try { legacyAnon = publicKey.split('.').length === 3 && /^[A-Za-z0-9_.-]+$/.test(publicKey) && JSON.parse(Buffer.from(publicKey.split('.')[1], 'base64url').toString()).role === 'anon'; } catch {}
  if (!/^sb_publishable_[A-Za-z0-9_-]+$/.test(publicKey) && !legacyAnon) throw new Error('ANON_KEY must be a Supabase public publishable or legacy anon key.');
}

export function buildPlan({ channel, buildNumber, client, firebase, production, clientConfigPath, environment = {}, flutter = 'flutter' }) {
  const preset = channels[channel];
  if (!preset) throw new Error('Choose testflight, play-internal, production-ios or production-android.');
  if (!/^[1-9]\d*$/.test(buildNumber ?? '')) throw new Error('An explicit positive --build-number is required.');
  const [platform, mode] = preset;
  const firebaseEnv = mode === 'test' ? 'dev' : 'prod';
  validatePublicClient(client, mode);
  if (mode === 'live' && (!production || production.paymentEnvironment !== 'live' || !production.supabaseUrl)) {
    throw new Error('Production requires --production-config with paymentEnvironment live and supabaseUrl.');
  }
  const expectedBackend = mode === 'test' ? betaBackend : production.supabaseUrl;
  let backend;
  try { backend = new URL(expectedBackend); } catch {}
  if (!backend || backend.protocol !== 'https:' || backend.username || backend.password || backend.search || backend.hash || backend.origin !== expectedBackend || client.SUPABASE_URL !== expectedBackend) throw new Error('Client backend does not match the selected channel configuration.');
  if (firebase.FIREBASE_ENV !== firebaseEnv || !firebase[`FIREBASE_${platform.toUpperCase()}_API_KEY`]) throw new Error(`Channel requires configured Firebase ${firebaseEnv} settings.`);
  for (const name of ['PAYMENT_ENV', 'STRIPE_ENV', 'CORTINA_ENV']) {
    const value = environment[name];
    if (value && !(mode === 'test' ? ['test', 'sandbox', 'dev'] : ['live', 'production', 'prod']).includes(value)) {
      throw new Error(`${name} conflicts with the selected payment environment.`);
    }
  }
  const defines = `--dart-define-from-file=config/firebase/${firebaseEnv}/${platform}.defines.json`;
  const clientFile = mode === 'test' ? 'config/client/test.defines.json' : clientConfigPath;
  if (!clientFile) throw new Error('Production requires --production-config with public client settings.');
  const common = ['--release', `--build-number=${buildNumber}`, defines,
    `--dart-define-from-file=${clientFile}`, `--dart-define=CLIENT_CHANNEL=${channel}`];
  const commands = platform === 'android'
    ? [[flutter, 'build', 'appbundle', ...common, '--target-platform=android-arm64', '--android-project-arg=kotlin.compiler.execution.strategy=in-process', '--android-project-arg=android.builder.sdkDownload=false']]
    : [[flutter, 'build', 'ios', '--config-only', '--no-codesign', ...common],
      ['/usr/bin/xcrun', 'xcodebuild', '-workspace', 'ios/Runner.xcworkspace', '-scheme', 'Runner', '-configuration', 'Release', '-sdk', 'iphoneos', '-destination', 'generic/platform=iOS', '-jobs', '1', '-quiet', '-derivedDataPath', 'build/ios/DerivedData', '-archivePath', `build/ios/archive/${channel}-${buildNumber}.xcarchive`, '-allowProvisioningUpdates', 'DEVELOPMENT_TEAM=3843FZGZ7T', 'CODE_SIGN_STYLE=Automatic', 'SWIFT_ENABLE_BATCH_MODE=NO', 'archive']];
  return { channel, platform, paymentEnvironment: mode, firebaseEnvironment: firebaseEnv, buildNumber, commands };
}

export function readReleaseConfiguration(options, projectRoot = root) {
  const preset = channels[options.channel];
  if (!preset) throw new Error('An explicit valid --channel is required.');
  const [platform, mode] = preset;
  if (mode === 'live' && !options['production-config']) throw new Error('Production requires --production-config with public client settings.');
  if (mode === 'test' && options['production-config']) throw new Error('Beta channels always select config/client/test.defines.json.');
  // Still bundled for local-run compatibility: inspect safety, never select it.
  const bundled = parseEnv(readFileSync(resolve(projectRoot, '.env'), 'utf8'));
  validatePublicClient(bundled, bundled.STRIPE_PUBLISHABLE_KEY?.startsWith('pk_live_') ? 'live' : 'test');
  const clientConfigPath = mode === 'test' ? 'config/client/test.defines.json' : resolve(options['production-config']);
  const config = JSON.parse(readFileSync(resolve(projectRoot, clientConfigPath), 'utf8'));
  const allowed = mode === 'test' ? publicFields : [...publicFields, 'paymentEnvironment', 'supabaseUrl'];
  if (!config || typeof config !== 'object' || Array.isArray(config) || Object.keys(config).some(key => !allowed.includes(key))) throw new Error('Client config contains unsupported fields; only public release settings are allowed.');
  if (publicFields.some(key => typeof config[key] !== 'string' || !config[key])) throw new Error('Complete public client settings are required.');
  return {
    channel: options.channel, buildNumber: options['build-number'], clientConfigPath,
    client: Object.fromEntries(publicFields.map(key => [key, config[key]])),
    production: mode === 'live' ? config : undefined,
    firebase: JSON.parse(readFileSync(resolve(projectRoot, `config/firebase/${mode === 'test' ? 'dev' : 'prod'}/${platform}.defines.json`), 'utf8')),
  };
}

export function parseArguments(args) {
  const options = {};
  for (let index = 0; index < args.length; index++) {
    const name = args[index];
    if (name === '--check') { options.check = true; continue; }
    if (!['--channel', '--build-number', '--production-config'].includes(name) || !args[index + 1] || args[index + 1].startsWith('--') || options[name.slice(2)] !== undefined) throw new Error('Use --channel NAME --build-number NUMBER [--production-config PATH] [--check]. Extra Flutter overrides are not accepted.');
    options[name.slice(2)] = args[++index];
  }
  return options;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const options = parseArguments(process.argv.slice(2));
    const preset = channels[options.channel];
    if (!preset) throw new Error('An explicit valid --channel is required.');
    const [platform] = preset;
    const plan = buildPlan({ ...readReleaseConfiguration(options),
      environment: process.env, flutter: process.env.FLUTTER_BIN || 'flutter' });
    console.log(JSON.stringify(plan)); // Public command arguments only; never client configuration.
    if (!options.check) {
      const env = { ...process.env, FLUTTER_TOOL_ARGS: '--old_gen_heap_size=512', CI: 'true', FLUTTER_SUPPRESS_ANALYTICS: 'true' };
      if (platform === 'android') env.GRADLE_OPTS = "-Dorg.gradle.jvmargs='-Xmx3072m -XX:MaxMetaspaceSize=512m -XX:ActiveProcessorCount=1' -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dorg.gradle.daemon=false";
      for (const [command, ...args] of plan.commands) {
        const result = spawnSync(command, args, { cwd: root, env, stdio: 'inherit' });
        if (result.error || result.status !== 0) throw new Error('Native build failed; inspect build output.');
      }
    }
  } catch (error) {
    // Parsing errors can contain source fragments. Only intentional validation messages are safe.
    console.error(error instanceof SyntaxError || error.code ? 'Cannot read or parse release configuration.' : error.message);
    process.exitCode = 1;
  }
}
