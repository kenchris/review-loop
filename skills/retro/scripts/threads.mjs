#!/usr/bin/env node
// Work with the review threads exported by fetch-threads.ps1 (threads.jsonl), offline. Node only, no packages.
//
//   threads.mjs import-md <export.md> [--out f]           the older markdown export as threads.jsonl, so it can be ingested
//   threads.mjs ingest <threads.jsonl>                    add new threads to the ledger, update the status of known ones, report what changed
//   threads.mjs list [--verdict v] [--pr n] [--status s]  show the ledger
//   threads.mjs verdict <id-prefix> <v> [--commit sha] [--note text]
//                                                         record a decision: fixed | rejected | caught | missed | deferred (new = undecided)
//   threads.mjs verdict --batch <file.tsv>               many decisions at once: one per line, <id-prefix> TAB <v> [TAB commit [TAB note]]; all or none
//   threads.mjs worksheet [--reports dir] [--all]         a retro worksheet: undecided or missed threads, each with the review-report entry near it
//   threads.mjs cases --evals dir [--prefix p] [--group g] [--repo-dir d] [--tag] [--force]
//                                                         eval cases from threads whose verdict is "fixed" (verified, and the fix landed)
//
// The ledger is $THREADS_LEDGER, or --ledger, or $REVIEWS_DIR/threads-ledger.json (default ./reviews). It holds one entry per thread, so a
// later export shows only what is new. Exports and the ledger contain review comments and code from the repository: keep them with the
// repository's private notes, never in the public tool.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const argv = process.argv.slice(2);
const cmd = argv.shift();
const opt = {};
const pos = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) {
    const k = argv[i].slice(2);
    opt[k] = argv[i + 1] !== undefined && !argv[i + 1].startsWith('--') ? argv[++i] : true;
  } else pos.push(argv[i]);
}

const VERDICTS = ['new', 'fixed', 'rejected', 'caught', 'missed', 'deferred'];
const today = new Date().toISOString().slice(0, 10);
const ledgerPath = opt.ledger || process.env.THREADS_LEDGER || path.join(process.env.REVIEWS_DIR || 'reviews', 'threads-ledger.json');

const die = (msg, code = 2) => { console.error('threads: ' + msg); process.exit(code); };
const loadLedger = () => (fs.existsSync(ledgerPath) ? JSON.parse(fs.readFileSync(ledgerPath, 'utf8')) : {});
const saveLedger = (ledger) => {
  fs.mkdirSync(path.dirname(ledgerPath), { recursive: true });
  const sorted = Object.fromEntries(Object.keys(ledger).sort().map((k) => [k, ledger[k]]));
  fs.writeFileSync(ledgerPath, JSON.stringify(sorted, null, 1) + '\n');
};
const oneLine = (s) => String(s || '').replace(/\s+/g, ' ').trim();
const firstSentence = (s, n) => {
  const t = oneLine(s);
  const m = t.search(/[.!?](\s|$)/);
  return m > 0 && m < n ? t.slice(0, m + 1) : t.slice(0, n);
};
const short = (id) => id.slice(-8);
const git = (args, dir) => execFileSync('git', args, { cwd: dir || process.cwd(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
const gitOk = (args, dir) => { try { git(args, dir); return true; } catch { return false; } };

function resolveId(ledger, prefix) {
  const hits = Object.keys(ledger).filter((k) => k === prefix || k.startsWith(prefix) || k.endsWith(prefix));
  if (hits.length === 0) die(`no thread matches '${prefix}'`);
  if (hits.length > 1) die(`'${prefix}' matches ${hits.length} threads; give more of the id`);
  return hits[0];
}

function ingest() {
  const file = pos[0];
  if (!file) die('usage: threads.mjs ingest <threads.jsonl>');
  const rows = fs.readFileSync(file, 'utf8').split('\n').filter((l) => l.trim()).map((l, i) => {
    try { return JSON.parse(l.replace(/^﻿/, '')); } catch { return die(`${file}: line ${i + 1} is not JSON`); }
  });
  const ledger = loadLedger();
  const seen = new Set();
  const added = [];
  const changed = [];
  for (const t of rows) {
    if (!t.thread_id) die(`${file}: a line has no thread_id`);
    seen.add(t.thread_id);
    const core = {
      repo: t.repo, pr: t.pr, pr_title: t.pr_title, branch: t.branch, base_ref: t.base_ref, head_sha: t.head_sha, base_sha: t.base_sha,
      path: t.path, line: t.line, start_line: t.start_line, status: t.status, author: t.author, commit_reviewed: t.commit_reviewed,
      created_at: t.created_at, body: t.body, replies: Math.max(0, (t.comments || []).length - 1),
      bot: /\[bot\]|copilot/i.test(t.author || ''),
    };
    const e = ledger[t.thread_id];
    if (!e) {
      ledger[t.thread_id] = { ...core, verdict: 'new', first_seen: today, last_seen: today };
      added.push(t.thread_id);
    } else {
      if (e.status !== core.status) changed.push(`${short(t.thread_id)} #${t.pr}: ${e.status} -> ${core.status}`);
      Object.assign(e, core, { last_seen: today });
      delete e.gone;
    }
  }
  const gone = [];
  for (const [id, e] of Object.entries(ledger)) {
    // With --full the export is the complete set of open threads, so anything not in it is gone now; otherwise a thread first seen today is kept.
    if (!seen.has(id) && !e.gone && (opt.full || e.last_seen !== today)) { e.gone = true; gone.push(id); }
  }
  saveLedger(ledger);
  console.log(`${rows.length} thread(s) in the export: ${added.length} new, ${changed.length} changed status, ${gone.length} no longer exported`);
  for (const c of changed) console.log('  changed: ' + c);
  const undecided = Object.values(ledger).filter((e) => e.verdict === 'new' && !e.gone).length;
  console.log(`ledger: ${Object.keys(ledger).length} thread(s), ${undecided} undecided (${ledgerPath})`);
}

// The markdown export of the older exporter (### F<n> - PR #<n> - title blocks, plus a table of pull requests) as threads.jsonl lines.
function importMd() {
  const file = pos[0];
  if (!file) die('usage: threads.mjs import-md <export.md> [--out threads.jsonl]');
  const text = fs.readFileSync(file, 'utf8').replace(/^﻿/, '').replace(/\r\n/g, '\n');
  const meta = new Map();
  for (const row of text.split('\n')) {
    const m = row.match(/^\| \[#(\d+)\]\(https:\/\/github\.com\/([^/]+\/[^/]+)\/pull\/\d+\) \| `([^`]*)` \| `([^`]*)` \| `?([0-9a-f]{7,40})`? .*?\| `([0-9a-f]{7,40})` \|/);
    if (m) meta.set(m[1], { repo: m[2], branch: m[3], base_ref: m[4], base_sha: m[5], head_sha: m[6] });
  }
  const blocks = text.split(/^(?=### F\d+ - PR #\d+ - )/m).filter((b) => /^### F\d+ - PR #\d+ - /.test(b));
  const out = [];
  for (const b of blocks) {
    const head = b.match(/^### (F\d+) - PR #(\d+) - (.*)$/m);
    const kv = (k) => ((b.match(new RegExp('^- [*][*]' + k + ':[*][*][ \t]*(.*)$', 'm')) || [])[1] || '').trim();
    const pr = parseInt(head[2], 10);
    const mt = meta.get(String(pr)) || {};
    const lines = kv('Line[(]s[)]').match(/(\d+)(?:-(\d+))?/) || [];
    const comment = (b.match(/^- \*\*Comment \(verbatim\):\*\*\n([\s\S]*?)(?=^- \*\*Code at that location:\*\*|\n### |$(?![\s\S]))/m) || [])[1] || '';
    const body = comment.split('\n').filter((l) => l.startsWith('>')).map((l) => l.replace(/^> ?/, '')).join('\n').trim();
    const commit = kv('Commit reviewed');
    const path_ = kv('File');
    const thread = kv('Thread') || `md:${pr}:${path_}:${lines[1] || ''}:${commit.slice(0, 7)}`;
    out.push(JSON.stringify({
      repo: mt.repo || '', pr, pr_title: head[3], pr_author: '', branch: mt.branch || (kv('PR / branch').match(/^(\S+)/) || [])[1] || '',
      base_ref: mt.base_ref || '', head_sha: mt.head_sha || '', base_sha: mt.base_sha || '', thread_id: thread, status: kv('Status') || 'open',
      path: path_, line: lines[2] ? parseInt(lines[2], 10) : parseInt(lines[1] || '0', 10) || null, start_line: parseInt(lines[1] || '0', 10) || null,
      commit_reviewed: commit, author: kv('Author'), created_at: '', body, comments: [{ id: null, author: kv('Author'), body, created_at: '', commit }],
    }));
  }
  const dest = opt.out && opt.out !== true ? opt.out : 'threads.jsonl';
  fs.writeFileSync(dest, out.length ? out.join('\n') + '\n' : '');
  console.log(`${out.length} thread(s) from ${file} -> ${dest} (${meta.size} pull request row(s) read)`);
}

function list() {
  const ledger = loadLedger();
  const rows = Object.entries(ledger).filter(([, e]) =>
    (!opt.verdict || e.verdict === opt.verdict) && (!opt.pr || String(e.pr) === String(opt.pr)) && (!opt.status || e.status === opt.status));
  for (const [id, e] of rows) {
    console.log(`${short(id)}  #${e.pr}  ${e.path}:${e.line}  ${e.author}  ${e.status}${e.gone ? '/gone' : ''}  ${e.verdict}  ${firstSentence(e.body, 110)}`);
  }
  console.log(`${rows.length} thread(s)`);
}

// Many decisions in one call (the triage skill uses it). Every line is checked before anything is written: one bad id or verdict stops the lot.
function batchVerdicts(file) {
  if (!fs.existsSync(file)) die(`no such file: ${file}`);
  const ledger = loadLedger();
  const rows = [];
  fs.readFileSync(file, 'utf8').split(/\r?\n/).forEach((line, i) => {
    if (!line.trim() || line.startsWith('#')) return;
    const [prefix, v = '', commit = '', ...note] = line.split('\t');
    if (!prefix.trim() || !VERDICTS.includes(v.trim())) die(`${file}:${i + 1}: need <id-prefix> TAB <${VERDICTS.join('|')}> [TAB commit [TAB note]]`);
    rows.push({ id: resolveId(ledger, prefix.trim()), v: v.trim(), commit: commit.trim(), note: note.join('\t').trim() });
  });
  if (rows.length === 0) die(`${file}: no decisions in it`);
  for (const r of rows) {
    const e = ledger[r.id];
    e.verdict = r.v;
    e.decided = today;
    if (r.commit && r.commit !== '-') e.fixed_in = r.commit;
    if (r.note && r.note !== '-') e.note = r.note;
  }
  saveLedger(ledger);
  for (const r of rows) {
    const e = ledger[r.id];
    console.log(`${short(r.id)} #${e.pr} ${e.path}:${e.line}: ${r.v}${e.fixed_in && r.commit && r.commit !== '-' ? ' in ' + e.fixed_in : ''}`);
  }
  console.log(`${rows.length} decision(s) recorded`);
}

function verdict() {
  if (opt.batch && opt.batch !== true) return batchVerdicts(opt.batch);
  const [prefix, v] = pos;
  if (!prefix || !VERDICTS.includes(v)) die(`usage: threads.mjs verdict <id-prefix> <${VERDICTS.join('|')}> [--commit sha] [--note text]`);
  const ledger = loadLedger();
  const id = resolveId(ledger, prefix);
  const e = ledger[id];
  e.verdict = v;
  e.decided = today;
  if (opt.commit && opt.commit !== true) e.fixed_in = opt.commit;
  if (opt.note && opt.note !== true) e.note = opt.note;
  saveLedger(ledger);
  console.log(`${short(id)} #${e.pr} ${e.path}:${e.line}: ${v}${e.fixed_in ? ' in ' + e.fixed_in : ''}`);
}

function reportEntries(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.md'))) {
    for (const line of fs.readFileSync(path.join(dir, f), 'utf8').split('\n')) {
      const m = line.match(/^(?:##\s+)?(F\d+)\s+(\S+?):(\d+)/);
      if (m) out.push({ report: f, id: m[1], file: m[2].replace(/\\/g, '/'), line: parseInt(m[3], 10) });
    }
  }
  return out;
}

function worksheet() {
  const ledger = loadLedger();
  const reports = reportEntries(opt.reports || process.env.REVIEWS_DIR || 'reviews');
  const rows = Object.entries(ledger).filter(([, e]) => !e.gone && (opt.all || e.verdict === 'new' || e.verdict === 'missed'));
  let withHint = 0;
  const lines = [];
  for (const [id, e] of rows) {
    const tp = String(e.path || '').replace(/\\/g, '/');
    const hit = reports.find((r) => (tp.endsWith(r.file) || r.file.endsWith(tp)) && Math.abs((e.line || 0) - r.line) <= 15);
    if (hit) withHint++;
    lines.push(`| ${short(id)} | #${e.pr} | \`${tp}:${e.line}\` | ${e.author}${e.bot ? '' : ' (human)'} | ${e.status} | ${e.verdict} | ${firstSentence(e.body, 160).replace(/\|/g, '/')} | ${hit ? `${hit.report} ${hit.id}` : ''} |`);
  }
  console.log(`# Retro worksheet (${today})\n`);
  console.log(`${rows.length} thread(s); ${withHint} have a self-review report entry within 15 lines (likely caught), ${rows.length - withHint} have none (candidate misses).\n`);
  console.log('A report hint is a hint only: confirm that the entry names the same defect, then record `caught`, or `missed` with the cause (references/miss-causes.md). Human comments come first in importance.\n');
  console.log('| thread | PR | where | author | status | verdict | comment | report hint |\n|---|---|---|---|---|---|---|---|');
  lines.sort((a, b) => (a.includes('(human)') ? 0 : 1) - (b.includes('(human)') ? 0 : 1));
  for (const l of lines) console.log(l);
}

function cases() {
  const evals = opt.evals && opt.evals !== true ? opt.evals : process.env.EVALS_DIR;
  if (!evals) die('usage: threads.mjs cases --evals <dir> [--prefix p] [--group g] [--repo-dir d] [--tag] [--force]');
  const prefix = opt.prefix && opt.prefix !== true ? opt.prefix : 'thr-';
  const repoDir = opt['repo-dir'] && opt['repo-dir'] !== true ? opt['repo-dir'] : process.cwd();
  const ledger = loadLedger();
  const groups = new Map();
  for (const [id, e] of Object.entries(ledger)) {
    if (e.verdict !== 'fixed' || !e.commit_reviewed) continue;
    const key = `${e.pr}@${e.commit_reviewed}`;
    if (!groups.has(key)) groups.set(key, { pr: e.pr, tip: e.commit_reviewed, e0: e, threads: [] });
    groups.get(key).threads.push([id, e]);
  }
  let made = 0;
  for (const g of groups.values()) {
    const caseId = `${prefix}${g.pr}-${g.tip.slice(0, 7)}`;
    const dir = path.join(evals, caseId);
    if (fs.existsSync(dir) && !opt.force) { console.log(`skip ${caseId}: exists (use --force)`); continue; }
    if (!gitOk(['cat-file', '-e', g.tip + '^{commit}'], repoDir)) { console.log(`skip ${caseId}: commit ${g.tip.slice(0, 9)} is not in ${repoDir}`); continue; }
    let base = '';
    if (g.e0.base_sha && gitOk(['cat-file', '-e', g.e0.base_sha + '^{commit}'], repoDir)) {
      try { base = git(['merge-base', g.tip, g.e0.base_sha], repoDir); } catch { base = ''; }
    }
    if (!base || base === g.tip) { console.log(`skip ${caseId}: no usable base (base ${String(g.e0.base_sha).slice(0, 9)} not in the repository, or the range is empty)`); continue; }
    const rejected = Object.values(ledger).filter((e) => e.pr === g.pr && e.commit_reviewed === g.tip && e.verdict === 'rejected');
    const L = [];
    L.push(`Case: ${caseId}`);
    L.push(`Range: ${base}..${g.tip}`);
    L.push(`Source: review threads on pull request #${g.pr} of ${g.e0.repo || 'the repository'} (${g.e0.branch}), each confirmed in the code and fixed (ledger verdict "fixed"). Rejected threads are listed as comments and are not findings.`);
    L.push(`Date: ${today}`);
    if (opt.group && opt.group !== true) L.push(`Groups: ${opt.group}`);
    L.push('', 'Findings (one per line: id | path:line | class | the defect, in a sentence):', '');
    g.threads.sort((a, b) => String(a[1].path).localeCompare(String(b[1].path)) || (a[1].line || 0) - (b[1].line || 0));
    g.threads.forEach(([id, e], i) => L.push(`F${i + 1} | ${e.path}:${e.line} | ? | ${firstSentence(e.body, 260).replace(/\|/g, '/')}  (thread ${short(id)})`));
    if (rejected.length) {
      L.push('', '# Rejected without a code change (not findings; do not add them):');
      for (const e of rejected) L.push(`# ${e.path}:${e.line} | ${firstSentence(e.body, 140)}${e.note ? '  [' + oneLine(e.note) + ']' : ''}`);
    }
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'case.md'), L.join('\n') + '\n');
    if (opt.tag) { try { git(['tag', '-f', `eval/${caseId}`, g.tip], repoDir); } catch { console.log(`could not tag eval/${caseId}`); } }
    console.log(`${caseId}: ${g.threads.length} finding(s), ${base.slice(0, 9)}..${g.tip.slice(0, 9)}`);
    made++;
  }
  console.log(`${made} case(s) written to ${evals}${opt.tag ? ' (tips tagged eval/<id>)' : '; tag the tips with --tag so they survive history rewrites'}`);
}

switch (cmd) {
  case 'import-md': importMd(); break;
  case 'ingest': ingest(); break;
  case 'list': list(); break;
  case 'verdict': verdict(); break;
  case 'worksheet': worksheet(); break;
  case 'cases': cases(); break;
  default: die('usage: threads.mjs import-md|ingest|list|verdict|worksheet|cases ... (see the top of the file)');
}
