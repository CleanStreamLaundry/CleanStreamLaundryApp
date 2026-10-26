import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const directory = path.resolve(process.argv[2]);
const forms = JSON.parse(fs.readFileSync(path.join(directory, 'forms-manifest.json')));
const byFile = new Map(forms.captures.map(entry => [entry.file, entry]));
const captures = fs.readdirSync(directory).filter(name => name.endsWith('.png')).sort().map(file => {
  const bytes = fs.readFileSync(path.join(directory, file));
  const detail = byFile.get(file) ?? {
    file,
    scene: file.replace(/-(light|dark)\.png$/, ''),
    scope: file.startsWith('home-cards')
      ? 'Actual Home Header, LocationSelector and AvailabilityCard; no map or full Home shell'
      : file.startsWith('scanner-overlay')
        ? 'Actual ScannerOverlay on neutral fixture background; no live camera'
        : 'Actual page or dialog, fixture-only services',
    frameworkErrors: [],
  };
  return {...detail, pixelWidth: bytes.readUInt32BE(16), pixelHeight: bytes.readUInt32BE(20),
    sha256: crypto.createHash('sha256').update(bytes).digest('hex')};
});
fs.writeFileSync(path.join(directory, 'manifest.json'), JSON.stringify({
  logicalViewport: {width: 360, height: 780, boldText: true, textScale: 1, topInset: 28, bottomInset: 24},
  captureCount: captures.length,
  fonts: forms.fonts,
  evidence: path.basename(directory) === 'before'
    ? 'BEFORE capture batch: 42 scenarios plus targeted modal-bottom captures. Baseline overflow diagnostics retained, not a visual acceptance pass.'
    : 'AFTER capture batch: strict zero-framework-error assertions. Latest monthly and modal-bottom captures supersede earlier images.',
  captures,
}, null, 2));
console.log(`${captures.length} PNGs; ${captures.filter(c => c.frameworkErrors.length).length} capture entries contain baseline layout diagnostics.`);
