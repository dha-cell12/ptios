import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXWireRoute} from './ax-wire-baseline.mjs';
const before=readFileSync(new URL('../../test/fixtures/streamd-privhelper-before-c06r.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function scriptHelperScope(source){const a=source.indexOf('// BEGIN script-bound direct helper stop scope.'),b=source.indexOf('// END script-bound direct helper stop scope.\n\n',a);assert.ok(a>=0&&b>a);return source.slice(a,b+'// END script-bound direct helper stop scope.\n\n'.length);}
export function restoreStreamdHelperStop(source){
    source=restoreAXWireRoute(source,'troll');
    const a=source.indexOf('static int TLinkRunPrivhelper(NSArray<NSString *> *arguments, int timeoutMs)'),b=source.indexOf('static int TLinkRunPrivhelperOpenBundle(',a);assert.ok(a>=0&&b>a);
    const scoped=source.replace(source.slice(a,b),before).replace(scriptHelperScope(source),'')
        .replace('static NSString *TLinkScriptRunTaskForSession(TLinkScriptSession *session, int taskType, NSString *body);\n','');
    assert.equal((scoped.match(/TLinkScriptRunTaskForSession\((session|weakSession), /g)||[]).length,7,'all generic/direct script task call sites bound');
    const restored=scoped.replaceAll(/TLinkScriptRunTaskForSession\((?:session|weakSession), /g,'TLinkScriptRunTask(');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'4a163f45b43fa6ea794569d14ed92dfce233fbf2ff38bbf0b8584669c7dcbc64',
        'complete pre-C06r server/task/authority/JS/consumer/recovery source');
    return restored;
}
