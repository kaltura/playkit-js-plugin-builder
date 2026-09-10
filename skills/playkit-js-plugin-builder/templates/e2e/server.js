// Minimal static file server for the e2e/demo pages. No new dependency: this project's own
// reference/testing-strategy.md says to serve the e2e test page with the CSP as a response header
// from the dev server; Node's built-in `http`/`fs` is enough for that, so this avoids adding
// `http-server`/`serve` just to set one header.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.env.E2E_PORT) || 4321;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.mp4': 'video/mp4',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8'
};

const server = http.createServer((req, res) => {
  const requestUrl = new URL(req.url, `http://localhost:${PORT}`);
  const requestedPath = decodeURIComponent(requestUrl.pathname);
  const filePath = path.join(ROOT, requestedPath);

  // Guard against path traversal outside the project root.
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.stat(filePath, (statErr, stats) => {
    if (statErr || !stats.isFile()) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    const ext = path.extname(filePath);
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    const baseHeaders = {
      'Content-Type': contentType,
      'Accept-Ranges': 'bytes',
      // The enforcing CSP header reference/security-checklist.md §3 requires on the e2e page.
      'Content-Security-Policy': "require-trusted-types-for 'script'"
    };

    // Real browsers need HTTP Range support to seek within a video: without it, Chromium reports
    // `video.seekable` as only `[0, 0]` even once the whole file is loaded, so `currentTime = X`
    // silently snaps back to 0. A plain 200-with-full-body response never exercises this; unit
    // tests can't catch it because they never load a real HTMLMediaElement over HTTP.
    const range = req.headers.range;
    if (range) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(range);
      if (match) {
        const start = match[1] ? parseInt(match[1], 10) : 0;
        const end = match[2] ? parseInt(match[2], 10) : stats.size - 1;
        if (start >= 0 && end < stats.size && start <= end) {
          res.writeHead(206, {
            ...baseHeaders,
            'Content-Range': `bytes ${start}-${end}/${stats.size}`,
            'Content-Length': end - start + 1
          });
          fs.createReadStream(filePath, {start, end}).pipe(res);
          return;
        }
      }
      res.writeHead(416, {'Content-Range': `bytes */${stats.size}`});
      res.end();
      return;
    }

    res.writeHead(200, {...baseHeaders, 'Content-Length': stats.size});
    fs.createReadStream(filePath).pipe(res);
  });
});

server.listen(PORT, () => {
  // eslint-disable-next-line no-console -- e2e-only dev server, not shipped plugin code (src/ bans console via ESLint).
  console.log(`e2e static server listening on http://localhost:${PORT}`);
});
