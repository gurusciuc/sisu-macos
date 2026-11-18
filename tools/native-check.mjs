import {fixture} from './fixture.mjs';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile} from 'node:fs/promises';
import {tmpdir,release} from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import assert from 'node:assert/strict';
import {setTimeout as sleep} from 'node:timers/promises';

const executable=path.resolve(process.argv[2]),out=path.resolve(process.argv[3]||'dist/results');
const home=await mkdtemp(path.join(tmpdir(),'sisu-webkit-check-')),f=await fixture();
await mkdir(out,{recursive:true});
let child,pending=new Map(),sequence=0,stderr='',exits=[];
const evidence={host:{platform:process.platform,arch:process.arch,kernel:release()},checks:{},snapshots:[],exits};
async function save(){await writeFile(path.join(out,'native-check.json'),JSON.stringify({...evidence,reports:Object.fromEntries(f.states),userAgents:Object.fromEntries(f.agents),hits:f.hits},null,2)+'\n');await writeFile(path.join(out,'runtime.log'),stderr);}
function launch(run,privateMode=false){
  assert(!child||child.exitCode!==null,'Previous launch still running');
  child=spawn(executable,['--test-control=stdio','--url='+f.url+'/?run='+run,...(privateMode?['--private']:[])],{env:{...process.env,BROWSER_TEST_HOME:home},stdio:['pipe','pipe','pipe']});
  child.stderr.on('data',data=>{stderr+=data});
  readline.createInterface({input:child.stdout}).on('line',line=>{try{const r=JSON.parse(line),p=pending.get(r.id);if(p){pending.delete(r.id);clearTimeout(p.timer);p.resolve(r.result);}}catch{stderr+=line+'\n';}});
  child.once('exit',(code,signal)=>{exits.push({run,code,signal});for(const p of pending.values()){clearTimeout(p.timer);p.reject(Error('App exited during request'));}pending.clear();console.log(JSON.stringify({exited:run,code,signal}));});
  console.log(JSON.stringify({launch:run,pid:child.pid,private:privateMode}));
}
function command(op,args={}){const id=++sequence;return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{pending.delete(id);reject(Error('Timed out: '+op));},45000);pending.set(id,{resolve,reject,timer});child.stdin.write(JSON.stringify({id,op,...args})+'\n');});}
async function report(run){for(let i=0;i<400;i++){if(f.states.has(run))return f.states.get(run);if(child.exitCode!==null)throw Error('App exited before fixture report');await sleep(100);}throw Error('Missing report: '+run);}
async function quit(){if(child.exitCode!==null)return;const exited=new Promise(resolve=>child.once('exit',resolve));await command('quit');await Promise.race([exited,sleep(12000).then(()=>{throw Error('App failed to quit');})]);assert.equal(child.exitCode,0);}
async function state(){return JSON.parse(await command('eval',{source:'JSON.stringify({documentId,draft:document.querySelector("textarea").value,dark:matchMedia("(prefers-color-scheme: dark)").matches,marker:localStorage.getItem("marker"),cookie:document.cookie,width:innerWidth,height:innerHeight,userAgent:navigator.userAgent})'}));}
try{
  launch('wk-first');let initial=await command('snapshot');assert.equal(initial.compiledRules,true);assert.equal(initial.persistent,true);assert.equal(initial.private,false);
  const first=await report('wk-first');assert.equal(first.prior,'empty');assert.equal(first.cookieBefore,'');assert.equal(first.hidden,'true');assert.equal(first.control,'true');
  const anchor=initial.selected;await command('eval',{source:'document.querySelector("textarea").value="A draft that must survive native tab and layout changes"; true'});
  const before=await state();
  assert.equal(before.userAgent,f.agents.get('wk-first'));assert.match(before.userAgent,/Version\/[\d.]+ Safari\/605\.1\.15 Sisu\//);evidence.checks.http_and_javascript_browser_identity=true;
  await command('layout',{value:'left'});const left=await state();assert.equal(left.documentId,before.documentId);assert.equal(left.draft,before.draft);
  await command('layout',{value:'top'});const top=await state();assert.equal(top.documentId,before.documentId);assert.equal(top.draft,before.draft);
  await command('theme',{value:'light'});await sleep(250);const light=await state();assert.equal(light.dark,false);assert.equal(light.documentId,before.documentId);assert.equal(light.draft,before.draft);
  await command('theme',{value:'dark'});await sleep(250);const dark=await state();assert.equal(dark.dark,true);assert.equal(dark.documentId,before.documentId);
  const second=await command('new',{url:f.url+'/?run=wk-second'});await report('wk-second');
  await command('select',{tab:anchor});const returned=await state();assert.equal(returned.documentId,before.documentId);assert.equal(returned.draft,before.draft);
  await command('close',{tab:second.selected});assert.equal((await command('snapshot')).selected,anchor);
  evidence.snapshots.push({initial,before,left,top,light,dark,returned});
  evidence.checks.live_layout_theme_and_background_close=true;await quit();

  launch('wk-restart');const restarted=await command('snapshot');const restart=await report('wk-restart');
  assert.equal(restarted.profileID,initial.profileID);assert.equal(restart.prior,'wk-second');assert.match(restart.cookieBefore,/fixture=wk-second/);evidence.checks.restart_persistence=true;await quit();
  const prefs=await readFile(path.join(home,'sisu-webkit/preferences.json'),'utf8');
  for(const run of ['wk-private-first','wk-private-second']){
    launch(run,true);const snap=await command('snapshot'),r=await report(run);
    assert.equal(snap.persistent,false);assert.equal(snap.profileID,'');assert.equal(r.prior,'empty');assert.equal(r.cookieBefore,'');
    await command('layout',{value:'left'});await quit();assert.equal(await readFile(path.join(home,'sisu-webkit/preferences.json'),'utf8'),prefs);
  }
  evidence.checks.private_separation=true;
  launch('wk-after-private');await command('snapshot');const after=await report('wk-after-private');assert.equal(after.prior,'wk-restart');assert.match(after.cookieBefore,/fixture=wk-restart/);
  assert(f.hits.includes('/probe-ad.js?allowed'));assert(!f.hits.includes('/probe-ad.js?direct'));assert(!f.hits.includes('/probe-ad.js?redirect'));
  evidence.checks.network_and_cosmetic_controls=true;
  if(process.argv.includes('--hold')){
    await save();console.log('READY_UI: type snapshot for current state, finish to quit');
    for await(const input of readline.createInterface({input:process.stdin})){
      if(input==='snapshot'){const snap=await command('snapshot');evidence.snapshots.push({nativeUI:snap});console.log(JSON.stringify(snap));await save();}
      if(input==='finish'){await quit();break;}
    }
  }else await quit();
  assert(exits.every(e=>e.code===0&&e.signal===null));evidence.checks.clean_exit=true;await save();console.log('PASS: native WebKit flows');
}catch(error){evidence.failure=String(error.stack||error);await save();console.error(evidence.failure);process.exitCode=1;}
finally{f.server.closeAllConnections();f.server.close();}
