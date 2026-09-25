import { readFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import release from './release.json' with { type: 'json' };
if (!release.ready || !/^[a-f0-9]{64}$/.test(release.sha256 || '')) throw Error('A qualified release is required before deployment');
const file = new URL('./public' + release.path, import.meta.url);
const info = await stat(file);
if (info.size !== release.bytes) throw Error('Release size mismatch');
if (createHash('sha256').update(await readFile(file)).digest('hex') !== release.sha256) throw Error('Release checksum mismatch');
const updateFile = new URL(`./public/storagedaddy/updates/${release.filename}`, import.meta.url);
const updateInfo = await stat(updateFile);
if (updateInfo.size !== release.bytes ||
    createHash('sha256').update(await readFile(updateFile)).digest('hex') !== release.sha256) {
  throw Error('Sparkle update does not match the qualified download');
}
const feed = await readFile(new URL('./public/storagedaddy/updates/appcast.xml', import.meta.url), 'utf8');
if (!feed.includes(`url="https://storage.daddyrad.com/updates/${release.filename}"`) ||
    !feed.includes(`length="${release.bytes}"`)) {
  throw Error('Sparkle feed does not point to the qualified download');
}
console.log('Qualified DMG matches the download manifest.');
