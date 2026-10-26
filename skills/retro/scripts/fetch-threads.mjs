#!/usr/bin/env node
// Export the review threads of a repository's open pull requests to threads.jsonl (one thread per line). Node 18+, no packages.
//
//   fetch-threads.mjs --repo owner/name [--author login] [--out threads.jsonl] [--all-threads] [--response-file f.json]
//
// Run it on a machine that can reach GitHub, then read the result anywhere with threads.mjs.
//   --repo           owner/name, required (there is no default)
//   --author         only pull requests opened by this login (default: all)
//   --out            output file (default threads.jsonl)
//   --all-threads    include resolved threads (default: unresolved and outdated ones only)
//   --response-file  test mode: read the pull request list and the thread nodes from a JSON file of the shape
//                    { "pulls": [ <REST pull objects> ], "threads": { "<number>": [ <GraphQL reviewThreads nodes> ] } }
//                    instead of calling GitHub
//
// The token is $GH_TOKEN or $GITHUB_TOKEN, else the one git already holds for github.com (`git credential fill`); no gh CLI is needed.
// Behind a proxy set HTTPS_PROXY (and NO_PROXY): Node's own fetch ignores proxy settings, so this script tunnels through the proxy itself.
//
// One output line per thread:
//   { repo, pr, pr_title, pr_author, branch, base_ref, head_sha, base_sha, thread_id, status (open|outdated|resolved), path, line,
//     start_line, commit_reviewed, author, created_at, body, comments: [ { id, author, body, created_at, commit } ] }
// commit_reviewed is the commit the first comment was written on (originalCommit): the code the reviewer saw.
import fs from 'node:fs';
import https from 'node:https';
import http from 'node:http';
import tls from 'node:tls';
import { execFileSync } from 'node:child_process';

const argv = process.argv.slice(2);
const opt = {};
for (let i = 0; i < argv.length; i++) {
  if (!argv[i].startsWith('--')) { console.error(`fetch-threads: unexpected argument '${argv[i]}'`); process.exit(2); }
  const k = argv[i].slice(2);
  opt[k] = argv[i + 1] !== undefined && !argv[i + 1].startsWith('--') ? argv[++i] : true;
}
const die = (msg, code = 2) => { console.error('fetch-threads: ' + msg); process.exit(code); };
const repo = opt.repo === true ? '' : opt.repo;
if (!repo || !/^[^/\s]+\/[^/\s]+$/.test(repo)) die('--repo owner/name is required');
const [owner, name] = repo.split('/');
const out = opt.out && opt.out !== true ? opt.out : 'threads.jsonl';

function token() {
  const t = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
  if (t) return t.trim();
  try {
    const cred = execFileSync('git', ['credential', 'fill'], { input: 'protocol=https\nhost=github.com\n\n', encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
    const line = cred.split('\n').find((l) => l.startsWith('password='));
    if (line) return line.slice('password='.length).trim();
  } catch { /* fall through */ }
  return die('no GitHub token: set GH_TOKEN, or sign in so that git credential fill returns one', 1);
}

function viaProxy(host) {
  const p = process.env.HTTPS_PROXY || process.env.https_proxy;
  if (!p) return null;
  const no = (process.env.NO_PROXY || process.env.no_proxy || '').split(',').map((s) => s.trim().replace(/^\./, '')).filter(Boolean);
  if (no.some((n) => n === '*' || host === n || host.endsWith('.' + n))) return null;
  return new URL(p.includes('://') ? p : 'http://' + p);
}

// One HTTPS request, directly or through an HTTP proxy with CONNECT. Resolves { status, body }.
function request(method, host, urlPath, headers, payload) {
  return new Promise((resolve, reject) => {
    const send = (extra) => {
      const req = https.request({ host, port: 443, method, path: urlPath, headers: { 'User-Agent': 'review-loop', ...headers }, ...extra }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
      });
      req.on('error', reject);
      if (payload) req.write(payload);
      req.end();
    };
    const proxy = viaProxy(host);
    if (!proxy) { send({}); return; }
    const connectHeaders = { Host: `${host}:443` };
    if (proxy.username) connectHeaders['Proxy-Authorization'] = 'Basic ' + Buffer.from(`${decodeURIComponent(proxy.username)}:${decodeURIComponent(proxy.password)}`).toString('base64');
    const connect = http.request({ host: proxy.hostname, port: proxy.port || 80, method: 'CONNECT', path: `${host}:443`, headers: connectHeaders });
    connect.on('connect', (res, socket) => {
      if (res.statusCode !== 200) { socket.destroy(); reject(new Error(`the proxy answered CONNECT with ${res.statusCode}`)); return; }
      // The connection comes from the agent's createConnection: the request-level option of that name is ignored when an agent is in use.
      const agent = new https.Agent({ keepAlive: false });
      agent.createConnection = () => tls.connect({ socket, servername: host });
      send({ agent });
    });
    connect.on('error', reject);
    connect.end();
  });
}

async function api(method, urlPath, body, tok) {
  const res = await request(method, 'api.github.com', urlPath,
    { Authorization: `Bearer ${tok}`, Accept: 'application/vnd.github+json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body ? JSON.stringify(body) : undefined);
  if (res.status < 200 || res.status >= 300) throw new Error(`GitHub answered ${res.status} for ${method} ${urlPath}: ${res.body.slice(0, 200)}`);
  return JSON.parse(res.body);
}

async function openPulls(tok) {
  const all = [];
  for (let page = 1; ; page++) {
    const batch = await api('GET', `/repos/${repo}/pulls?state=open&per_page=100&page=${page}`, null, tok);
    all.push(...batch);
    if (batch.length < 100) return all;
  }
}

const QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated path line originalLine startLine originalStartLine diffSide
          comments(first: 50) {
            nodes { databaseId body author { login } createdAt commit { oid } originalCommit { oid } replyTo { databaseId } }
          }
        }
      }
    }
  }
}`;

async function threadsOf(number, tok) {
  const nodes = [];
  let after = null;
  for (;;) {
    const res = await api('POST', '/graphql', { query: QUERY, variables: { owner, name, number, after } }, tok);
    if (res.errors) throw new Error('GraphQL: ' + JSON.stringify(res.errors));
    const block = res.data.repository.pullRequest.reviewThreads;
    nodes.push(...block.nodes);
    if (!block.pageInfo.hasNextPage) return nodes;
    after = block.pageInfo.endCursor;
  }
}

async function main() {
  let pulls, threadsFor, tok = null;
  if (opt['response-file'] && opt['response-file'] !== true) {
    const fixture = JSON.parse(fs.readFileSync(opt['response-file'], 'utf8').replace(/^﻿/, ''));
    pulls = fixture.pulls || [];
    threadsFor = async (n) => (fixture.threads && fixture.threads[String(n)]) || [];
  } else {
    tok = token();
    pulls = await openPulls(tok);
    threadsFor = (n) => threadsOf(n, tok);
  }
  const lines = [];
  for (const pr of pulls) {
    if (opt.author && opt.author !== true && (pr.user || {}).login !== opt.author) continue;
    for (const t of await threadsFor(pr.number)) {
      if (!t || (!opt['all-threads'] && t.isResolved)) continue;
      const comments = (t.comments && t.comments.nodes) || [];
      if (comments.length === 0) continue;
      const root = comments[0];
      const commitOf = (c) => (c.originalCommit && c.originalCommit.oid) || (c.commit && c.commit.oid) || '';
      const line = t.line || t.originalLine || null;
      lines.push(JSON.stringify({
        repo,
        pr: pr.number,
        pr_title: pr.title || '',
        pr_author: (pr.user || {}).login || '',
        branch: (pr.head || {}).ref || '',
        base_ref: (pr.base || {}).ref || '',
        head_sha: (pr.head || {}).sha || '',
        base_sha: (pr.base || {}).sha || '',
        thread_id: t.id,
        status: t.isResolved ? 'resolved' : t.isOutdated ? 'outdated' : 'open',
        path: t.path || '',
        line,
        start_line: t.startLine || t.originalStartLine || line,
        commit_reviewed: commitOf(root),
        author: (root.author || {}).login || '',
        created_at: root.createdAt || '',
        body: root.body || '',
        comments: comments.map((c) => ({ id: c.databaseId, author: (c.author || {}).login || '', body: c.body || '', created_at: c.createdAt || '', commit: commitOf(c) })),
      }));
    }
  }
  fs.writeFileSync(out, lines.length ? lines.join('\n') + '\n' : '');
  console.log(`${lines.length} thread(s) from ${pulls.length} open pull request(s) -> ${out}`);
}

main().catch((e) => die(e.message, 1));
