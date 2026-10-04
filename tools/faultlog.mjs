// Collect HarmonyOS JS crash (jscrash) reports for this app and print the root-cause lines.
//
// Why this exists: `hdc shell cat/ls /data/log/...` is DENIED (that runs as the shell user),
// but `hdc file recv` of a KNOWN path works, because it goes through the hdc daemon.
// Filenames can be listed through hidumper's Faultlogger service (SA 1201).
//
// Adapted from Delsin-Yu/JustPDF (.agents/skills/arkts-runtime-fix/scripts/probe-faultlogger.mjs
// and fetch-faultlog.mjs, Apache-2.0) and rewritten as a single dependency-free script.
// Node (not .ps1) on purpose: Windows execution policy blocks unsigned .ps1 scripts,
// and `pwsh` is not guaranteed to be on PATH here.
//
// Usage:
//   node tools/faultlog.mjs                  # newest 3 for the default bundle
//   node tools/faultlog.mjs --all            # every matching report
//   node tools/faultlog.mjs --bundle com.x.y --hdc "C:\path\to\hdc.exe"

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const DEFAULTS = {
  bundle: 'com.leaif.yibook',
  hdc: 'F:\\deveco\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe',
  out: 'faultlog',
  limit: 3,
};

const REMOTE_DIR = '/data/log/faultlog/faultlogger';

function parseArgs(argv) {
  const map = new Map();
  for (let i = 0; i < argv.length; i += 1) {
    const t = argv[i];
    if (!t.startsWith('--')) {
      continue;
    }
    const key = t.slice(2);
    const val = argv[i + 1];
    if (val === undefined || val.startsWith('--')) {
      map.set(key, true);
      continue;
    }
    map.set(key, val);
    i += 1;
  }
  return map;
}

function hdc(args, encoding) {
  return execFileSync(DEFAULTS.hdc, args, {
    encoding: encoding ?? 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 64 * 1024 * 1024,
  });
}

function printKv(pairs) {
  for (const [k, v] of Object.entries(pairs)) {
    process.stdout.write(`${k}: ${v}\n`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const hdcPath = typeof args.get('hdc') === 'string' ? args.get('hdc') : DEFAULTS.hdc;
  DEFAULTS.hdc = hdcPath;

  const bundle = typeof args.get('bundle') === 'string' ? args.get('bundle') : DEFAULTS.bundle;
  const outDir = typeof args.get('out') === 'string' ? args.get('out') : DEFAULTS.out;
  const limit = typeof args.get('limit') === 'string' ? Number(args.get('limit')) : DEFAULTS.limit;
  const all = args.get('all') === true;

  if (!fs.existsSync(DEFAULTS.hdc)) {
    printKv({ status: 'probe_failed', reason: `hdc not found: ${DEFAULTS.hdc}`, next_action: 'pass --hdc <path>' });
    process.exit(2);
  }

  // 1) List candidate filenames. -LogSuffixWithMs makes hidumper include timestamps.
  let dump = '';
  try {
    dump = hdc(['shell', "hidumper -s 1201 -a '-p Faultlogger -LogSuffixWithMs'"]);
  } catch (err) {
    printKv({ status: 'probe_failed', reason: String(err.message ?? err), next_action: 'check the device is connected and unlocked' });
    process.exit(1);
  }

  const tail = bundle.split('.').pop();
  const names = [...new Set(
    dump.split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l.includes('jscrash') && l.includes(tail)),
  )];

  if (names.length === 0) {
    printKv({
      status: 'not_found',
      bundle,
      matched: 0,
      next_action: 'reproduce the crash, then run this script again.',
    });
    process.exit(0);
  }

  const picked = all ? names : names.slice(-limit);
  fs.mkdirSync(outDir, { recursive: true });

  printKv({ status: 'found', bundle, matched: names.length, fetching: picked.length });

  for (const name of picked) {
    const local = path.join(outDir, name);
    try {
      hdc(['file', 'recv', `${REMOTE_DIR}/${name}`, local]);
    } catch (err) {
      process.stdout.write(`\n=== ${name}: RECV FAILED ===\n${String(err.message ?? err)}\n`);
      continue;
    }
    if (!fs.existsSync(local)) {
      process.stdout.write(`\n=== ${name}: local file missing after recv ===\n`);
      continue;
    }

    const lines = fs.readFileSync(local, 'utf8').split(/\r?\n/);
    process.stdout.write(`\n=== ${name} ===\n`);
    for (const l of lines) {
      if (/^(Device info|Build info|Reason|Error name|Error message):/.test(l)) {
        process.stdout.write(`${l.trim()}\n`);
      }
    }
    // App / Pen-Kit level frames name the offending file; framework noise is skipped.
    const frames = lines.filter((l) => /^\s*at .*\((entry|penkit|@hw-|hsp|.*\.ets)/.test(l)).slice(0, 5);
    if (frames.length > 0) {
      process.stdout.write('--- frames ---\n');
      for (const f of frames) {
        process.stdout.write(`${f.trim()}\n`);
      }
    }
    process.stdout.write(`saved: ${local}\n`);
  }

  process.stdout.write('\nnext_action: fix the Error message above; the frames name the importing file.\n');
}

main();
