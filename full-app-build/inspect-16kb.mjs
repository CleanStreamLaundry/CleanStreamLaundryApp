import { createReadStream, closeSync, constants, accessSync, mkdirSync, mkdtempSync,
  openSync, unlinkSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const apk = process.argv[2] ?? '/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/build/app/outputs/apk/debug/app-debug.apk';
const expected = process.argv[3] ?? 'ffaf0c1ba176c8b1ae82c70698430008c289bf0f13ec7d761e2c29abafbe756b';
if (!/^[a-f0-9]{64}$/.test(expected)) throw new Error('Expected APK SHA-256 required');
const zipalign = '/Users/jamaki604/Library/Android/sdk/build-tools/36.0.0/zipalign';
const readelf = '/Users/jamaki604/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf';
const unzip = '/usr/bin/unzip';
const root = process.argv[4] ?? dirname(fileURLToPath(import.meta.url));
const report = { apk, expectedSha256: expected, scope: 'Packaged 64-bit ELF static inspection; ARM32 inventory only', libraries: [] };
let output;

async function sha256(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

function run(tool, args, stdout = 'pipe') {
  const result = spawnSync(tool, args, {
    encoding: 'utf8', timeout: 60000, maxBuffer: 8 * 1024 * 1024,
    stdio: ['ignore', stdout, 'pipe'], env: { ...process.env, LC_ALL: 'C' },
  });
  if (result.error || result.signal || result.status === null) {
    throw new Error(`Tool did not finish: ${tool}: ${result.error?.message ?? result.signal}`);
  }
  return result;
}

try {
  report.sha256Before = await sha256(apk);
  if (report.sha256Before !== expected) throw new Error('APK SHA mismatch; stop, do not inspect replacement');
  for (const tool of [zipalign, readelf, unzip]) accessSync(tool, constants.X_OK);
  mkdirSync(join(root, '16kb-results'), { recursive: true });
  output = mkdtempSync(join(root, '16kb-results', 'inspection-'));
  const listing = run(unzip, ['-Z1', apk]);
  if (listing.status !== 0) throw new Error(`ZIP inventory failed: ${listing.stderr}`);
  const entries = listing.stdout.trim().split(/\r?\n/);
  const libraries = entries.filter((name) => !name.endsWith('/') && (name.startsWith('lib/') || name.endsWith('.so')));
  if (!libraries.length || libraries.length > 128 || new Set(libraries).size !== libraries.length) {
    throw new Error('Empty, excessive or duplicate native-library inventory');
  }
  if (libraries.some((name) => !/^lib\/(arm64-v8a|armeabi-v7a|x86_64)\/[A-Za-z0-9_.+-]+\.so$/.test(name))) {
    throw new Error('Unexpected native-library path/ABI; requires scoped review');
  }
  writeFileSync(join(output, 'native-libraries.json'), JSON.stringify(libraries, null, 2) + '\n');
  const zipLog = openSync(join(output, 'zipalign.txt'), 'wx');
  let zip;
  try { zip = run(zipalign, ['-c', '-P', '16', '-v', '4', apk], zipLog); }
  finally { closeSync(zipLog); }
  report.zipalignExit = zip.status;
  writeFileSync(join(output, 'zipalign-stderr.txt'), zip.stderr);

  for (const [index, name] of libraries.entries()) {
    const abi = name.split('/')[1];
    const evaluated16kb = abi !== 'armeabi-v7a';
    const identity = {
      'arm64-v8a': [/Class:\s+ELF64/, /Machine:\s+AArch64/],
      'armeabi-v7a': [/Class:\s+ELF32/, /Machine:\s+ARM\s*$/m],
      x86_64: [/Class:\s+ELF64/, /Machine:\s+(?:Advanced Micro Devices X86-64|AMD x86-64)/],
    }[abi];
    const temporary = join(output, 'current-library.so');
    const fd = openSync(temporary, 'wx');
    let extracted;
    try { extracted = run(unzip, ['-p', apk, name], fd); }
    finally { closeSync(fd); }
    try {
      if (extracted.status !== 0) throw new Error(`Extraction failed: ${name}`);
      const elf = run(readelf, ['--wide', '--file-header', '--program-headers', temporary]);
      writeFileSync(join(output, `${index}-readelf.txt`), elf.stdout + elf.stderr);
      if (elf.status !== 0 || !identity.every((pattern) => pattern.test(elf.stdout))) {
        throw new Error(`ELF class/machine does not match packaged ABI: ${name}`);
      }
      const segments = elf.stdout.split('\n').map((line) => line.trim().split(/\s+/))
        .filter((fields) => fields[0] === 'LOAD' || fields[0] === 'GNU_RELRO');
      const failures = [];
      const loads = segments.filter((fields) => fields[0] === 'LOAD');
      if (!loads.length) throw new Error(`No parsed LOAD segments: ${name}`);
      for (const fields of segments) {
        const values = [fields[1], fields[2], fields[5], fields.at(-1)];
        if (values.some((value) => !/^0x[0-9a-f]+$/i.test(value ?? ''))) {
          throw new Error(`Unrecognized program-header format: ${name}`);
        }
        const [offset, address, memorySize, alignment] = values.map((value) => BigInt(value));
        if (!evaluated16kb) continue;
        if (fields[0] === 'LOAD') {
          if (alignment < 16384n || (alignment & (alignment - 1n)) !== 0n) {
            failures.push(`LOAD alignment ${fields.at(-1)} below 16 KB or not power-of-two`);
          }
          if (offset % 16384n !== address % 16384n) failures.push('LOAD offset/address not congruent modulo 16 KB');
        } else if ((address + memorySize) % 16384n !== 0n) {
          failures.push(`GNU_RELRO end not 16 KB aligned: address=${fields[2]} size=${fields[5]}`);
        }
      }
      report.libraries.push({ name, abi, evaluated16kb, loadSegments: loads.length,
        relroSegments: segments.length - loads.length, failures });
    } finally { unlinkSync(temporary); }
  }
  report.sha256After = await sha256(apk);
  if (report.sha256After !== expected) throw new Error('APK changed during inspection');
  report.passed = report.zipalignExit === 0 && report.libraries.every((library) => !library.failures.length);
  process.exitCode = report.passed ? 0 : 1;
} catch (error) {
  report.passed = false;
  report.error = error.message;
  process.exitCode = 2;
}
if (output) writeFileSync(join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ ...report, output }, null, 2));
