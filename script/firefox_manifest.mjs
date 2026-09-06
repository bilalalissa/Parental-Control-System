import { readFile, writeFile } from 'node:fs/promises';
// Generate a browser-specific manifest, never duplicate the policy implementation.
const [source, destination] = process.argv.slice(2);
if (!source || !destination) throw new Error('Expected source and destination manifest paths');
const manifest = JSON.parse(await readFile(source, 'utf8'));
delete manifest.key;
delete manifest.version_name;
manifest.background = { scripts: ['website-policy.js', 'service-worker.js'] };
manifest.browser_specific_settings = { gecko: {
  id: 'parental-control@bilalalissa.com', strict_min_version: '133.0'
} };
await writeFile(destination, JSON.stringify(manifest, null, 2) + '\n');
