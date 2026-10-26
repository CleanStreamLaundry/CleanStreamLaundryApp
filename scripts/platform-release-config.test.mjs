import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

// Source-only macOS preflight. No SDK, build, assets or network required.
const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const manifest = read('android/app/src/main/AndroidManifest.xml');
const info = read('ios/Runner/Info.plist');
const privacy = read('ios/Runner/PrivacyInfo.xcprivacy');
const xpath = (source, expression) => execFileSync('/usr/bin/xmllint', [
  '--nonet', '--xpath', expression, '-',
], { input: source, encoding: 'utf8' }).trim();
const plist = source => JSON.parse(execFileSync('/usr/bin/plutil', [
  '-convert', 'json', '-o', '-', '-',
], { input: source, encoding: 'utf8' }));
const android = name => `@*[local-name()='${name}' and namespace-uri()='http://schemas.android.com/apk/res/android']`;
const permissionCount = (source, name) => Number(xpath(source,
  `count(/manifest/uses-permission[${android('name')}='android.permission.${name}'])`));
const assertLocationPair = source => {
  assert.equal(permissionCount(source, 'ACCESS_FINE_LOCATION'), 1);
  assert.equal(permissionCount(source, 'ACCESS_COARSE_LOCATION'), 1);
};
const assertUniqueKeys = source => assert.equal(
  Number(xpath(source, 'count(//dict/key[. = preceding-sibling::key])')), 0,
  'Duplicate plist dictionary keys are ambiguous',
);

test('Android requests foreground fine and coarse location together', () => {
  assertLocationPair(manifest);
  assert.equal(permissionCount(manifest, 'ACCESS_BACKGROUND_LOCATION'), 0);
  assert.equal(permissionCount(manifest, 'FOREGROUND_SERVICE_LOCATION'), 1);
  const servicePermission = `/manifest/uses-permission[${android('name')}='android.permission.FOREGROUND_SERVICE_LOCATION']`;
  assert.equal(xpath(manifest,
    `string(${servicePermission}/@*[local-name()='node' and namespace-uri()='http://schemas.android.com/tools'])`), 'remove');
});

test('location regression guard rejects a fine-only manifest', () => {
  const fineOnly = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    + '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/></manifest>';
  assert.throws(() => assertLocationPair(fineOnly), assert.AssertionError);
});

test('Android retains network, camera and notification permissions without broad media access', () => {
  for (const name of ['INTERNET', 'CAMERA', 'POST_NOTIFICATIONS']) {
    assert.equal(permissionCount(manifest, name), 1);
  }
  for (const name of ['RECORD_AUDIO', 'READ_MEDIA_IMAGES', 'READ_MEDIA_VIDEO', 'MANAGE_EXTERNAL_STORAGE']) {
    assert.equal(permissionCount(manifest, name), 0);
  }
});

test('Android removes inherited advertising ID and ad attribution permissions', () => {
  for (const name of [
    'com.google.android.gms.permission.AD_ID',
    'android.permission.ACCESS_ADSERVICES_AD_ID',
    'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
  ]) {
    const node = `/manifest/uses-permission[${android('name')}='${name}']`;
    assert.equal(Number(xpath(manifest, `count(${node})`)), 1, name);
    assert.equal(xpath(manifest,
      `string(${node}/@*[local-name()='node' and namespace-uri()='http://schemas.android.com/tools'])`), 'remove', name);
  }
});

test('Android optional Firebase collection and automatic init remain disabled', () => {
  for (const name of [
    'firebase_analytics_collection_enabled',
    'google_analytics_automatic_screen_reporting_enabled',
    'google_analytics_adid_collection_enabled',
    'google_analytics_default_allow_ad_personalization_signals',
    'firebase_messaging_auto_init_enabled',
    'firebase_inapp_messaging_auto_data_collection_enabled',
  ]) {
    const node = `/manifest/application/meta-data[${android('name')}='${name}']`;
    assert.equal(Number(xpath(manifest, `count(${node})`)), 1);
    assert.equal(xpath(manifest, `string(${node}/${android('value')})`), 'false');
  }
});

test('Android starts with the splash theme and then retains the payment-compatible normal theme', () => {
  const activity = `/manifest/application/activity[${android('name')}='.MainActivity']`;
  assert.equal(xpath(manifest, `string(${activity}/${android('theme')})`), '@style/LaunchTheme');
  const normal = `${activity}/meta-data[${android('name')}='io.flutter.embedding.android.NormalTheme']`;
  assert.equal(xpath(manifest, `string(${normal}/${android('resource')})`), '@style/NormalTheme');
  for (const qualifier of ['values', 'values-night', 'values-v31', 'values-night-v31']) {
    const styles = read(`android/app/src/main/res/${qualifier}/styles.xml`);
    assert.equal(Number(xpath(styles, 'count(/resources/style[@name="LaunchTheme"])')), 1);
    assert.equal(xpath(styles, 'string(/resources/style[@name="NormalTheme"]/@parent)'),
      'Theme.MaterialComponents.DayNight.NoActionBar.Bridge');
  }
});

test('Android night launch resources preserve artwork on the dark app background', () => {
  for (const qualifier of ['drawable-night', 'drawable-night-v21']) {
    const background = read(`android/app/src/main/res/${qualifier}/launch_background.xml`);
    for (const [name, gravity] of [['background', 'fill'], ['splash', 'center']]) {
      const bitmap = `/layer-list/item/bitmap[${android('src')}='@drawable/${name}']`;
      assert.equal(Number(xpath(background, `count(${bitmap})`)), 1);
      assert.equal(xpath(background, `string(${bitmap}/${android('gravity')})`), gravity);
    }
  }
  const modern = read('android/app/src/main/res/values-night-v31/styles.xml');
  assert.equal(xpath(modern, 'string(/resources/style[@name="LaunchTheme"]/item[@name="android:windowSplashScreenBackground"])'), '#212121');
  assert.equal(xpath(modern, 'string(/resources/style[@name="LaunchTheme"]/item[@name="android:windowSplashScreenAnimatedIcon"])'), '@drawable/android12splash');
});

test('iOS plist keys are unique and high-refresh behavior is preserved', () => {
  assertUniqueKeys(info);
  assertUniqueKeys(privacy);
  assert.equal(plist(info).CADisableMinimumFrameDurationOnPhone, true);
});

test('iOS launch surface follows OS appearance without changing the logo', () => {
  const storyboard = read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
  const view = '/document/scenes/scene/objects/viewController/view';
  assert.equal(xpath(storyboard, `string(${view}/color[@key="backgroundColor"]/@name)`), 'LaunchSurface');
  assert.equal(xpath(storyboard, `string(${view}/subviews/view/color[@key="backgroundColor"]/@name)`), 'LaunchSurface');
  assert.equal(xpath(storyboard, `string(${view}/subviews/imageView/@image)`), 'LaunchImage');
  assert.equal(xpath(storyboard, `string(${view}/subviews/imageView/@contentMode)`), 'scaleAspectFit');
  const { colors } = JSON.parse(read('ios/Runner/Assets.xcassets/LaunchSurface.colorset/Contents.json'));
  assert.equal(colors.length, 2);
  const light = colors.find(item => !item.appearances);
  const dark = colors.find(item => item.appearances?.some(appearance => appearance.appearance === 'luminosity' && appearance.value === 'dark'));
  for (const color of [light, dark]) {
    assert.equal(color.idiom, 'universal');
    assert.equal(color.color['color-space'], 'srgb');
    assert.equal(color.color.components.alpha, '1.000');
  }
  for (const channel of ['red', 'green', 'blue']) {
    assert.equal(Number(light.color.components[channel]), 1);
    assert.equal(Number(dark.color.components[channel]), 33);
  }
  assert.equal(plist(info).UIUserInterfaceStyle, undefined);
});

test('duplicate-key guard catches identical values before plist conversion loses them', () => {
  const duplicate = '<plist version="1.0"><dict><key>flag</key><true/>'
    + '<key>flag</key><true/></dict></plist>';
  assert.throws(() => assertUniqueKeys(duplicate), assert.AssertionError);
});

test('iOS existing purpose strings cover location, camera and photo selection', () => {
  const data = plist(info);
  for (const key of ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription', 'NSLocationWhenInUseUsageDescription']) {
    assert.equal(typeof data[key], 'string');
    assert.ok(data[key].trim().length > 0, key);
  }
  assert.equal(data.NSLocationAlwaysAndWhenInUseUsageDescription, undefined);
  assert.equal(data.NSMicrophoneUsageDescription, undefined);
});

test('iOS optional Firebase defaults stay off while push background mode is retained', () => {
  const data = plist(info);
  for (const key of [
    'FIREBASE_ANALYTICS_COLLECTION_ENABLED',
    'FirebaseAutomaticScreenReportingEnabled',
    'GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED',
    'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS',
    'FirebaseMessagingAutoInitEnabled',
    'FirebaseInAppMessagingAutomaticDataCollectionEnabled',
  ]) assert.equal(data[key], false, key);
  assert.deepEqual(data.UIBackgroundModes, ['remote-notification']);
});

test('existing UserDefaults reason and nontracking declarations remain unchanged', () => {
  const data = plist(privacy);
  assert.equal(data.NSPrivacyTracking, false);
  assert.deepEqual(data.NSPrivacyTrackingDomains, []);
  assert.deepEqual(data.NSPrivacyAccessedAPITypes, [{
    NSPrivacyAccessedAPIType: 'NSPrivacyAccessedAPICategoryUserDefaults',
    NSPrivacyAccessedAPITypeReasons: ['CA92.1'],
  }]);
  // This is declaration preservation, not certification of collection coverage.
});

test('approved iOS floor, app identities and privacy resource membership remain intact', () => {
  const project = plist(read('ios/Runner.xcodeproj/project.pbxproj'));
  const objects = project.objects;
  const runner = Object.values(objects).find(value => value.isa === 'PBXNativeTarget' && value.name === 'Runner');
  assert.ok(runner);
  for (const id of objects[runner.buildConfigurationList].buildConfigurations) {
    assert.equal(objects[id].buildSettings.PRODUCT_BUNDLE_IDENTIFIER,
      'com.cleanstreamlaundrysolutions.clenaStreamLaundryApp');
  }
  const projectConfigs = objects[objects[project.rootObject].buildConfigurationList].buildConfigurations;
  for (const id of projectConfigs) assert.equal(objects[id].buildSettings.IPHONEOS_DEPLOYMENT_TARGET, '15.0');
  const resources = runner.buildPhases.map(id => objects[id]).find(value => value.isa === 'PBXResourcesBuildPhase');
  assert.equal(resources.files.filter(id => objects[objects[id].fileRef]?.path === 'PrivacyInfo.xcprivacy').length, 1);
  assert.equal(plist(info).CFBundleIdentifier, '$(PRODUCT_BUNDLE_IDENTIFIER)');
  assert.match(read('ios/Podfile'), /^platform :ios, '15\.0'$/m);
  const gradle = read('android/app/build.gradle.kts');
  assert.match(gradle, /applicationId = "com\.cleanstreamlaundrysolutions\.clean_stream_laundry_app"/);
  assert.match(gradle, /targetSdk = flutter\.targetSdkVersion/);
});

test('Podfile enables only the existing camera capability in permission_handler', () => {
  const podfile = read('ios/Podfile');
  assert.deepEqual([...podfile.matchAll(/['"](PERMISSION_[A-Z_]+=1)['"]/g)].map(match => match[1]),
    ['PERMISSION_CAMERA=1']);
  assert.ok(plist(info).NSCameraUsageDescription.trim());
});

test('camera hook covers all plugin configurations, preserves definitions and leaves other pods alone', () => {
  const podfile = read('ios/Podfile');
  const start = podfile.indexOf('post_install do |installer|');
  assert.notEqual(start, -1);
  // Evaluate only the actual configuration hook with inert Ruby objects, not CocoaPods.
  const result = JSON.parse(execFileSync('/usr/bin/ruby', ['-rjson', '-e', `
    Config = Struct.new(:name, :build_settings)
    Target = Struct.new(:name, :build_configurations)
    Project = Struct.new(:targets)
    Installer = Struct.new(:pods_project)
    def post_install(&block); $hook = block; end
    def flutter_additional_ios_build_settings(target); $visited << target.name; end
    key = 'GCC_PREPROCESSOR_DEFINITIONS'
    plugin = Target.new('permission_handler_apple', [
      Config.new('Debug', {}),
      Config.new('Profile', {key => ['$(inherited)', 'EXISTING=1']}),
      Config.new('Release', {key => ['RELEASE_FLAG=1']})
    ])
    other = Target.new('unrelated_pod', [Config.new('Release', {key => ['OTHER=1']})])
    installer = Installer.new(Project.new([plugin, other]))
    $visited = []
    eval(ARGV.fetch(0), TOPLEVEL_BINDING, 'Podfile post_install')
    2.times { $hook.call(installer) }
    puts JSON.generate({plugin: plugin.build_configurations.map(&:build_settings),
      other: other.build_configurations.first.build_settings, visited: $visited})
  `, podfile.slice(start)], { encoding: 'utf8' }));
  assert.deepEqual(result.plugin.map(config => config.GCC_PREPROCESSOR_DEFINITIONS), [
    ['$(inherited)', 'PERMISSION_CAMERA=1'],
    ['$(inherited)', 'EXISTING=1', 'PERMISSION_CAMERA=1'],
    ['RELEASE_FLAG=1', '$(inherited)', 'PERMISSION_CAMERA=1'],
  ]);
  assert.deepEqual(result.other, { GCC_PREPROCESSOR_DEFINITIONS: ['OTHER=1'] });
  assert.deepEqual(result.visited, [
    'permission_handler_apple', 'unrelated_pod', 'permission_handler_apple', 'unrelated_pod',
  ]);
});
