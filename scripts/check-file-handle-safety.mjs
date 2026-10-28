import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [source,header,frozen]=await Promise.all(['shared/TLinkJSFileHandle.mm','shared/TLinkJSFileHandle.h','test/fixtures/js-file-handle-legacy-v1.inc'].map(read));
const between=(text,a,b)=>{const x=text.indexOf(a),y=text.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return text.slice(x,y);};
const old=frozen.slice(frozen.indexOf('\n')+1);
const line=between(source,'- (NSDictionary *)readLine','- (NSDictionary *)writeData:');
const oldLine=between(old,'- (NSDictionary *)readLine','- (NSDictionary *)writeData:');
const oldLoop=between(oldLine,'        BOOL eof = NO;','        if (data.length > 0)');
const loop=between(line,'        const int fd = _fd;','        if (data.length > 0)');
const restored=source.replace('#include "TLinkJSFileLine.h"\n','').replace('    BOOL _lineReadChunked;\n','').replace('    struct stat lineStat;\n    handle->_lineReadChunked = handle->_readable && fstat(fd, &lineStat) == 0 && S_ISREG(lineStat.st_mode) && lseek(fd, 0, SEEK_CUR) >= 0;\n','').replace(loop,oldLoop);
assert.equal(restored.trim(),old.trim(),'only readLine I/O and once-open regular-file selection change');
assert.match(line,/TLinkJSFileReadLine\(_maxTransferBytes, _lineReadChunked,[\s\S]*::read\(fd, bytes, count\)[\s\S]*::lseek\(fd, -static_cast<off_t>\(count\), SEEK_CUR\)[\s\S]*appendBytes:bytes length:count/);
assert.doesNotMatch(line,/read\(_fd, &byte, 1\)|NoCopy/);
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.ok((await read(path)).includes('node scripts/check-file-handle-safety.mjs'));
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-file-handle-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'file-line.exe':'file-line'),file=join(root,'test/file-handle-line-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);
    run(binary,[]);
    const names=['TLinkJSFileHandleCreateJSObject','TLinkJSFileModeIsValid','TLinkJSFileModeWrites','TLinkJSFileHandle'];
    const legacyHeader=header.replace(new RegExp(`\\b(${names.join('|')})\\b`,'g'),name=>`Legacy${name}`);
    assert.ok(legacyHeader.includes('@interface LegacyTLinkJSFileHandle : NSObject')&&legacyHeader.includes('JSValue *LegacyTLinkJSFileHandleCreateJSObject('));
    assert.doesNotMatch(legacyHeader,/LegacyLegacy/,'rename each complete legacy symbol once');
    await writeFile(join(temp,'LegacyFileHandle.h'),legacyHeader);
    if(process.platform==='darwin'){
        const runtime=join(temp,'file-handle-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','JavaScriptCore','-I',temp,'-I',join(root,'shared'),join(root,'test/file-handle-runtime-test.mm'),'-o',runtime]);
        run(runtime,[temp]);
    }else console.log('macOS actual/frozen FileHandle Foundation/POSIX/JSCore integration is included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-file-handle-'));await rm(temp,{recursive:true,force:true});}
