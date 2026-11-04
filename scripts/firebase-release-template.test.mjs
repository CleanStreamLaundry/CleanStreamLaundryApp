import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { releaseTemplate } from './firebase-release-template.mjs';

const example = JSON.parse(readFileSync(new URL('../config/firebase/release-policy.example.json', import.meta.url)));

test('template wraps the entire policy as a string with no targeting conditions', () => {
  const template = releaseTemplate(example);
  assert.deepEqual(template.conditions, []);
  assert.deepEqual(Object.keys(template.parameters), ['release_policy_v1']);
  const parameter = template.parameters.release_policy_v1;
  assert.equal(parameter.valueType, 'STRING');
  assert.deepEqual(JSON.parse(parameter.defaultValue.value), example);
});

test('checked-in defaults are nonblocking on both platforms without guessed store links', () => {
  assert.equal(example.schema, 1);
  for (const platform of ['android', 'ios']) {
    assert.deepEqual(example[platform], {
      minimum: '0.0.0', recommended: '0.0.0', blocked_builds: [],
      maintenance: false, update_url: '',
    });
  }
});

test('wrapping preserves platform-specific controls without mutating input', () => {
  const policy = structuredClone(example);
  Object.assign(policy.ios, {
    minimum: '1.2.0', recommended: '1.10.0', blocked_builds: [42],
    maintenance: true, update_url: 'https://apps.apple.com/app/id123456789',
  });
  const before = structuredClone(policy);
  assert.deepEqual(JSON.parse(releaseTemplate(policy).parameters.release_policy_v1.defaultValue.value), before);
  assert.deepEqual(policy, before);
});

test('local CLI emits the same deterministic JSON template', () => {
  const result = execFileSync(process.execPath, [
    new URL('./firebase-release-template.mjs', import.meta.url).pathname,
  ], { encoding: 'utf8' });
  assert.equal(result, `${JSON.stringify(releaseTemplate(example), null, 2)}\n`);
  assert.equal(result, readFileSync(new URL('../config/firebase/remoteconfig.template.json', import.meta.url), 'utf8'));
});
