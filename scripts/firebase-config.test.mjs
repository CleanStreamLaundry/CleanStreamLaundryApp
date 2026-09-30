import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const registrations = {
  dev: ['clean-stream-dev', '83380736317', '7b074a257825c9670af554', '3fe930785b224eb30af554'],
  prod: ['clean-stream-production', '863183154828', '3c15f3dbc067244de615a9', '1f263e0ea3df94bde615a9'],
};
const plist = path => JSON.parse(execFileSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', path]));
test('Runner has iOS 15, post-resources selector and push entitlements without signing changes', {skip: process.platform !== 'darwin'}, () => {
  const root = new URL('../', import.meta.url).pathname;
  const project = plist(join(root, 'ios/Runner.xcodeproj/project.pbxproj'));
  const objects = project.objects;
  const runner = Object.values(objects).find(o => o.isa === 'PBXNativeTarget' && o.name === 'Runner');
  const phases = runner.buildPhases.map(id => objects[id]);
  const resourceIndex = phases.findIndex(p => p.isa === 'PBXResourcesBuildPhase');
  const selector = phases[resourceIndex + 1];
  assert.equal(selector.name, 'Select Firebase Environment');
  assert.equal(Number(selector.alwaysOutOfDate), 1);
  assert.match(selector.shellScript, /xcrun --sdk macosx swift/);
  assert.equal(phases.filter(p => p.name === selector.name).length, 1);
  const projectConfig = objects[objects[project.rootObject].buildConfigurationList].buildConfigurations;
  for (const id of projectConfig) assert.equal(objects[id].buildSettings.IPHONEOS_DEPLOYMENT_TARGET, '15.0');
  const configs = objects[runner.buildConfigurationList].buildConfigurations;
  for (const id of configs) {
    const config = objects[id];
    assert.equal(config.buildSettings.APS_ENVIRONMENT, config.name === 'Debug' ? 'development' : 'production');
    assert.equal(config.buildSettings.CODE_SIGN_ENTITLEMENTS, 'Runner/Runner.entitlements');
    assert.equal(config.buildSettings.DEVELOPMENT_TEAM, '3843FZGZ7T');
    assert.equal(config.buildSettings.PRODUCT_BUNDLE_IDENTIFIER, 'com.cleanstreamlaundrysolutions.clenaStreamLaundryApp');
  }
  const entitlement = plist(join(root, 'ios/Runner/Runner.entitlements'));
  assert.equal(entitlement['aps-environment'], '$(APS_ENVIRONMENT)');
  assert.deepEqual(entitlement['com.apple.developer.associated-domains'], ['applinks:cleanstreamlaundry.com']);
  assert.deepEqual(plist(join(root, 'ios/Runner/Info.plist')).UIBackgroundModes, ['remote-notification']);
});
for (const [env, [project, sender, android, ios]] of Object.entries(registrations)) {
  test(`${env} Android config matches its registered identity and explicit build input`, () => {
    const root = new URL(`../config/firebase/${env}/`, import.meta.url);
    const config = JSON.parse(readFileSync(new URL('google-services.json', root)));
    const defines = JSON.parse(readFileSync(new URL('android.defines.json', root)));
    assert.equal(config.project_info.project_id, project);
    assert.equal(config.project_info.project_number, sender);
    const client = config.client[0];
    assert.equal(client.client_info.mobilesdk_app_id, `1:${sender}:android:${android}`);
    assert.equal(client.client_info.android_client_info.package_name, 'com.cleanstreamlaundrysolutions.clean_stream_laundry_app');
    assert.deepEqual(defines, { FIREBASE_ENV: env, FIREBASE_ANDROID_API_KEY: client.api_key[0].current_key });
  });
  test(`${env} iOS config matches its registered identity and explicit build input`, {skip: process.platform !== 'darwin'}, () => {
    const root = new URL(`../config/firebase/${env}/`, import.meta.url);
    const config = JSON.parse(execFileSync('/usr/bin/plutil', ['-convert','json','-o','-',new URL('GoogleService-Info.plist', root).pathname]));
    const defines = JSON.parse(readFileSync(new URL('ios.defines.json', root)));
    assert.equal(config.PROJECT_ID, project); assert.equal(config.GCM_SENDER_ID, sender);
    assert.equal(config.GOOGLE_APP_ID, `1:${sender}:ios:${ios}`);
    assert.equal(config.BUNDLE_ID, 'com.cleanstreamlaundrysolutions.clenaStreamLaundryApp');
    assert.equal(config.IS_ANALYTICS_ENABLED, false);
    assert.deepEqual(defines, { FIREBASE_ENV: env, FIREBASE_IOS_API_KEY: config.API_KEY });
  });
}

test('iOS native selector uses explicit environment and removes stale prod config', {skip: process.platform !== 'darwin'}, () => {
  const root = new URL('../', import.meta.url).pathname;
  const temporary = mkdtempSync(join(root, '.firebase-native-'));
  mkdirSync(join(temporary, 'Runner.app'));
  const output = join(temporary, 'Runner.app/GoogleService-Info.plist');
  const objects = plist(join(root, 'ios/Runner.xcodeproj/project.pbxproj')).objects;
  const phase = Object.values(objects).find(o => o.name === 'Select Firebase Environment');
  const run = defines => execFileSync('/bin/sh', ['-c', phase.shellScript], {env: {
      PATH: '/usr/bin:/bin', HOME: temporary, TMPDIR: temporary,
      DERIVED_FILE_DIR: temporary,
      SDKROOT: execFileSync('/usr/bin/xcrun', ['--sdk', 'iphoneos', '--show-sdk-path'], {encoding: 'utf8'}).trim(),
      CLANG_MODULE_CACHE_PATH: join(temporary, 'cache'),
      SRCROOT: join(root, 'ios'), BUILT_PRODUCTS_DIR: temporary, CONTENTS_FOLDER_PATH: 'Runner.app',
      DART_DEFINES: Object.entries(defines).map(([k,v]) => Buffer.from(`${k}=${v}`).toString('base64')).join(','),
    }});
  try {
    for (const env of ['dev', 'prod']) {
      run(JSON.parse(readFileSync(join(root, `config/firebase/${env}/ios.defines.json`))));
      assert.equal(execFileSync('/usr/bin/plutil', ['-extract','PROJECT_ID','raw',output], {encoding:'utf8'}).trim(), registrations[env][0]);
    }
    run({}); assert.equal(existsSync(output), false);
    const wrong = JSON.parse(readFileSync(join(root, 'config/firebase/prod/ios.defines.json')));
    wrong.FIREBASE_ENV = 'dev';
    assert.throws(() => run(wrong)); assert.equal(existsSync(output), false);
  } finally { rmSync(temporary, {recursive:true}); }
});
