import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('./public/storagedaddy/clarity.js', import.meta.url), 'utf8');

function run(hostname) {
  const inserted = [];
  const firstScript = { parentNode: { insertBefore(script) { inserted.push(script); } } };
  const document = {
    createElement() { return {}; },
    getElementsByTagName() { return [firstScript]; },
  };
  const window = { location: { hostname } };
  vm.runInNewContext(source, { document, window });
  return { inserted, window };
}

test('loads only the StorageDaddy Clarity project on the production hostname', () => {
  const production = run('storage.daddyrad.com');
  assert.equal(production.inserted.length, 1);
  assert.equal(production.inserted[0].src, `https://www.clarity.ms/tag/${'ymdr' + 'qo4jyc'}`);
  assert.equal(production.window.clarity.q.length, 1);
  assert.deepEqual(Array.from(production.window.clarity.q[0]), ['set', 'project_id', 'storagedaddy']);

  const local = run('localhost');
  assert.equal(local.inserted.length, 0);
  assert.equal(local.window.clarity, undefined);
});
