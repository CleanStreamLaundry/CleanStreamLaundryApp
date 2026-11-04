import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// The Dart ReleasePolicy parser is authoritative; this only wraps its payload.
export function releaseTemplate(policy) {
  return {
    conditions: [],
    parameters: {
      release_policy_v1: {
        defaultValue: { value: JSON.stringify(policy) },
        description: 'Client release controls; not backend authorization.',
        valueType: 'STRING',
      },
    },
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const input = process.argv[2] ?? new URL('../config/firebase/release-policy.example.json', import.meta.url);
  const policy = JSON.parse(readFileSync(input, 'utf8'));
  process.stdout.write(`${JSON.stringify(releaseTemplate(policy), null, 2)}\n`);
}
