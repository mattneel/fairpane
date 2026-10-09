import os from 'node:os';
import { Worker, SHARE_ENV, isMainThread } from 'node:worker_threads';
if (!isMainThread) { /* idle worker */ setTimeout(() => {}, 10); } else {
  const mode = process.argv[2];
  const show = label => { process.env.TMP = process.env.TEMP = process.env.TMPDIR = 'C:\\fairpane-probe-' + label; console.log(mode, label, os.tmpdir()); };
  show('before');
  if (mode !== 'none') { const w = new Worker(new URL(import.meta.url), mode === 'share' ? { env: SHARE_ENV } : {}); await new Promise(r => w.on('online', r)); show('after-start'); await w.terminate(); }
  show('after-stop');
  console.log(mode, 'SHARE_ENV type', typeof SHARE_ENV);
}
