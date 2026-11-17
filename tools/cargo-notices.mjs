import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const metadata = JSON.parse(execFileSync('cargo', ['metadata', '--locked', '--format-version', '1'], {cwd:root, maxBuffer:32*1024*1024}));
const entries=[], texts=new Map();
async function notices(dir, inside=false) {
  const found=[];
  for(const file of await readdir(dir,{withFileTypes:true})){
    const full=path.join(dir,file.name);
    if(file.isDirectory() && !inside && /^licen[cs]es?$/i.test(file.name)) found.push(...await notices(full,true));
    if(file.isFile() && (inside || /^(licen[cs]e|copying|copyright|notice)([._-]|$)/i.test(file.name))) found.push(full);
  }
  return found.sort();
}
for(const pkg of metadata.packages.filter(p=>p.source).sort((a,b)=>a.name.localeCompare(b.name)||a.version.localeCompare(b.version))){
  const dir=path.dirname(pkg.manifest_path), refs=[];
  for(const file of await notices(dir)){
    const body=(await readFile(file,'utf8')).trim().replaceAll('\r\n','\n');
    const id=createHash('sha256').update(body).digest('hex').slice(0,16);
    texts.set(id,body);refs.push(path.relative(dir,file).replaceAll('\\','/')+' ['+id+']');
  }
  entries.push([pkg.name+' '+pkg.version,pkg.license||'See upstream license file',
    'https://crates.io/crates/'+pkg.name+'/'+pkg.version, ...refs].join('\n'));
}
const contents=['Cargo.lock dependency notices','Includes build and platform-specific packages. Source packages remain available by version.',...entries,...[...texts].sort(([a],[b])=>a.localeCompare(b)).map(([id,body])=>'['+id+']\n'+body)].join('\n\n');
await writeFile(path.join(root,'notices/rust-dependencies.txt'),contents+'\n');
