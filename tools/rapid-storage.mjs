// Each process exits immediately after WebKit acknowledges the fixture's write.
import assert from 'node:assert/strict';
import http from 'node:http';
import {spawn} from 'node:child_process';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';
const exe=path.resolve(process.argv[2]), home=await mkdtemp(path.join(tmpdir(),'sisu-rapid-'));
let ready;
const server=http.createServer((req,res)=>{
  res.setHeader('Cache-Control','no-store');
  if(req.url==='/ready'){res.end('ok');ready();return;}
  res.setHeader('Content-Type','text/html');res.end('<title>Storage fixture</title><script>addEventListener("load",()=>fetch("/ready"))</script>');
});
server.listen(0,'127.0.0.1');await once(server,'listening');
const url='http://127.0.0.1:'+server.address().port+'/';
let child,misses=0;
async function launch(isPrivate,expected,write){
  const loaded=new Promise(resolve=>ready=resolve);
  child=spawn(exe,['--test-control=stdio','--url='+url,...(isPrivate?['--private']:[])],
    {env:{...process.env,BROWSER_TEST_HOME:home},stdio:['pipe','pipe','inherit']});
  const exit=once(child,'exit'), replies=readline.createInterface({input:child.stdout})[Symbol.asyncIterator]();
  let id=0;
  async function command(op,params={}){
    child.stdin.write(JSON.stringify({id:++id,op,...params})+'\n');
    for (;;) {const response=await replies.next();assert(!response.done);const data=JSON.parse(response.value);if(data.id===id)return data.result;}
  }
  await loaded;
  const source='(()=>{const old=localStorage.getItem("rapid");localStorage.setItem("rapid",'+JSON.stringify(write)+');return JSON.stringify([old,localStorage.getItem("rapid")])})()';
  const [old,ack]=JSON.parse(await command('eval',{source}));
  assert.equal(ack,write);
  await command('quit');assert.equal((await exit)[0],0);child=null;
  if(old!==expected){console.error('Mismatch', {isPrivate,expected,old});misses++;}
}
const deadline=setTimeout(()=>{child?.kill();server.closeAllConnections();console.error('Fixture deadline exceeded');process.exit(2);},120000);
try {
 let prior=null;
 for(let i=0;i<5;i++){const next=randomUUID();await launch(false,prior,next);prior=next;}
 await launch(true,null,randomUUID());await launch(true,null,randomUUID());
 await launch(false,prior,randomUUID());
 console.log(JSON.stringify({launches:8,misses}));assert.equal(misses,0);
}finally{clearTimeout(deadline);child?.kill();server.closeAllConnections();server.close();}
