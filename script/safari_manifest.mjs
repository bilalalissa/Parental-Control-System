import { readFile, writeFile } from 'node:fs/promises';

const [source, destination] = process.argv.slice(2);
if (!source || !destination) throw new Error('usage: safari_manifest.mjs source destination');

const manifest = JSON.parse(await readFile(source, 'utf8'));
delete manifest.key;
delete manifest.version_name;
delete manifest.incognito;
await writeFile(destination, `${JSON.stringify(manifest, null, 2)}\n`);
