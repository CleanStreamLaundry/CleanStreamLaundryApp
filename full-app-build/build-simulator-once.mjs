import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';

const app = '/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp';
const lane = path.dirname(new URL(import.meta.url).pathname);
const sdk = '/Users/jamaki604/CleanStreamProjects/.campaign-work/flutter-3.38.10';
const protectedPaths = ['pubspec.yaml', 'pubspec.lock', 'ios/Podfile', 'ios/Podfile.lock',
  'ios/Pods/Manifest.lock', 'ios/Runner.xcodeproj/project.pbxproj',
  'ios/Runner/Info.plist', 'ios/Flutter/Generated.xcconfig',
  'ios/Flutter/flutter_export_environment.sh'].map(p => path.join(app, p));
protectedPaths.push(path.join(lane, 'DerivedData/Build/Products/Release-iphoneos/Runner.app/Runner'));
const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const before = Object.fromEntries(protectedPaths.map(p => [p, hash(p)]));
const generated = fs.readFileSync(path.join(app, 'ios/Flutter/Generated.xcconfig'), 'utf8');
if (!generated.includes(`FLUTTER_ROOT=${sdk}\n`)) throw Error('Pinned Flutter root mismatch');
const defines = generated.match(/^DART_DEFINES=(.*)$/m)?.[1];
const decoded = defines?.split(',').map(v => Buffer.from(v, 'base64').toString());
if (!decoded?.includes('FIREBASE_ENV=dev')) throw Error('Generated Dev configuration missing');
if (hash(path.join(app, 'ios/Podfile.lock')) !== hash(path.join(app, 'ios/Pods/Manifest.lock'))) {
  throw Error('Pod lock mismatch');
}
const args = ['xcodebuild', '-workspace', 'ios/Runner.xcworkspace', '-scheme', 'Runner',
  '-configuration', 'Debug', '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator',
  '-jobs', '1', '-quiet', '-disableAutomaticPackageResolution', '-skipPackageUpdates',
  '-derivedDataPath', path.join(lane, 'SimulatorDerivedData'),
  'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO',
  'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_IDENTITY=', 'SWIFT_ENABLE_BATCH_MODE=NO',
  'FLUTTER_BUILD_MODE=debug', `FLUTTER_ROOT=${sdk}`,
  'FLUTTER_BUILD_DIR=../.campaign-work/firebase/full-app-build/simulator-flutter-build', 'build'];
const child = spawn('xcrun', args, { cwd: app, detached: true,
  env: { ...process.env, CI: 'true', FLUTTER_SUPPRESS_ANALYTICS: 'true',
    FLUTTER_TOOL_ARGS: '--old_gen_heap_size=512', COCOAPODS_DISABLE_STATS: 'true' },
  stdio: ['ignore', 'pipe', 'pipe'] });
let output = '';
child.stdout.on('data', data => { output += data; });
child.stderr.on('data', data => { output += data; });
const timeout = setTimeout(() => process.kill(-child.pid, 'SIGKILL'), 30 * 60 * 1000);
child.on('close', (code, signal) => {
  clearTimeout(timeout);
  let safe = output.split(defines).join('[DART_DEFINES omitted]');
  for (const entry of decoded) {
    const value = entry.slice(entry.indexOf('=') + 1);
    if (value.length > 12) safe = safe.split(value).join('[public config omitted]');
  }
  fs.writeFileSync(path.join(lane, 'simulator-build.log'), safe);
  const changed = protectedPaths.filter(p => hash(p) !== before[p]);
  const receipt = { exit: code, signal, changedProtectedPaths: changed,
    artifact: path.join(lane, 'SimulatorDerivedData/Build/Products/Debug-iphonesimulator/Runner.app') };
  fs.writeFileSync(path.join(lane, 'simulator-build-receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
  process.stdout.write(safe.slice(-12000));
  console.log(JSON.stringify(receipt));
  process.exitCode = code ?? 124;
});
