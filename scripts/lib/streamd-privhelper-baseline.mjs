import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyStreamdHelper=readFileSync(new URL('../../test/fixtures/streamd-privhelper-before-c06q.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function streamdHelper(source){const a=source.indexOf('static int TLinkRunPrivhelper(NSArray<NSString *> *arguments, int timeoutMs)'),b=source.indexOf('static int TLinkRunPrivhelperOpenBundle(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreStreamdPrivhelper(source){
    const actual=streamdHelper(source);
    const admission=actual.slice(actual.indexOf('    // BEGIN bounded streamd helper owner.'),actual.indexOf('    // END bounded streamd helper owner.\n')+'    // END bounded streamd helper owner.\n'.length);
    const wait=actual.slice(actual.indexOf('    // BEGIN bounded streamd helper wait.'),actual.indexOf('    // END bounded streamd helper wait.\n')+'    // END bounded streamd helper wait.\n'.length);
    const oldWait=legacyStreamdHelper.slice(legacyStreamdHelper.indexOf('    int status = 0;'),legacyStreamdHelper.lastIndexOf('}\n\n'));
    assert.equal(actual.replace(admission,'').replace('    if (rc == 0 && pid > 0) child.adopted(pid);\n','').replace(wait,oldWait),legacyStreamdHelper,
        'complete existing helper args/path/spawn/allocation/error source');
    const restored=source.replace('#include "../../shared/TLinkVPNHelperChild.h"\n','').replace(actual,legacyStreamdHelper);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'98182a2e470222e3db0c9f54447b71e183533e007b7881990c817291e905728e',
        'complete preceding streamd, task consumers, authority, scripts, shell/daemon watchers and fallback routing');
    return restored;
}
