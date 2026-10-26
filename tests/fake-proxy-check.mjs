// Starts a fake HTTP proxy that accepts CONNECT, runs fetch-threads.mjs against it (no response file) and prints what the proxy saw:
// the CONNECT line, and whether a TLS ClientHello (first byte 0x16) then arrived through the tunnel. If the script dialled GitHub directly
// instead of using the tunnel, no handshake arrives. Usage: node fake-proxy-check.mjs <fetch-threads.mjs>
import http from 'node:http';
import { spawn } from 'node:child_process';

const script = process.argv[2];
let seen = '';
let hello = false;
const server = http.createServer();
server.on('connect', (req, socket) => {
  seen = `CONNECT ${req.url}`;
  socket.on('error', () => {});
  socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
  socket.once('data', (d) => { hello = d[0] === 0x16; socket.destroy(); });
});
server.listen(0, '127.0.0.1', () => {
  const port = server.address().port;
  const child = spawn(process.execPath, [script, '--repo', 'o/r', '--out', process.platform === 'win32' ? 'NUL' : '/dev/null'], {
    env: { ...process.env, HTTPS_PROXY: `http://127.0.0.1:${port}`, https_proxy: '', NO_PROXY: '', no_proxy: '', GH_TOKEN: 'x' },
  });
  let err = '';
  child.stderr.on('data', (d) => { err += d; });
  const timer = setTimeout(() => { child.kill(); console.log('TIMEOUT'); server.close(); process.exit(1); }, 20000);
  child.on('exit', (code) => {
    clearTimeout(timer);
    console.log(`SAW: ${seen || '(nothing)'}`);
    console.log(`TLS HANDSHAKE THROUGH THE TUNNEL: ${hello ? 'yes' : 'no'}`);
    console.log(`EXIT: ${code}`);
    console.log(`ERR: ${err.trim().split('\n')[0]}`);
    server.close();
  });
});
