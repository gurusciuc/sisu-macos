import http from 'node:http';
import { readFile } from 'node:fs/promises';

export async function fixture() {
  const hits = [];
  const states = new Map();
  const html = await readFile(new URL('../fixtures/workload.html', import.meta.url), 'utf8');
  const capabilities=await readFile(new URL('../fixtures/capabilities.html',import.meta.url),'utf8');
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    hits.push(url.pathname + url.search);
    res.setHeader('Cache-Control', 'no-store');
    if(url.pathname==='/capabilities'){res.setHeader('Content-Type','text/html');return res.end(capabilities);}
    if(url.pathname==='/dedicated.js'||url.pathname==='/service.js'){
      res.setHeader('Content-Type','text/javascript');
      const probe= "async k=>{const allowed=await fetch('/control.js?'+k).then(r=>r.ok).catch(()=>false);const target=await fetch('/ads/!rotator/'+k).then(r=>r.ok).catch(()=>false);return {allowed,targetReached:target}}";
      return res.end(url.pathname==='/dedicated.js'?`(${probe})('dedicated').then(postMessage.bind(self))`:
        `onmessage=e=>e.waitUntil((${probe})('service').then(r=>e.ports[0].postMessage(r)))`);
    }
    if (url.pathname === '/report') {
      states.set(url.searchParams.get('run'), Object.fromEntries(url.searchParams));
      return res.end('ok');
    }
    if (url.pathname === '/bounce') {
      res.writeHead(302, { Location: '/probe-ad.js?redirect' }); return res.end();
    }
    if (url.pathname === '/subframe') {
      res.setHeader('Content-Type','text/html');
      return res.end('<title>Frame</title><script src="/probe-ad.js?frame"></script><input autocomplete="username">');
    }
    if (url.pathname.endsWith('.js') || url.pathname.startsWith('/ads/')) {
      res.setHeader('Content-Type','text/javascript');
      return res.end('globalThis.allowedControl = true;');
    }
    if (url.pathname === '/favicon.ico') { res.writeHead(204); return res.end(); }
    res.setHeader('Content-Type', 'text/html;charset=utf-8');
    return res.end(html);
  });
  await new Promise((resolve, reject) => server.once('error', reject).listen(0, '127.0.0.1', resolve));
  return { server, hits, states, url: 'http://localhost:' + server.address().port };
}
