import {restoreConsoleRetention} from './console-retention-baseline.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const consoleVectorBefore=()=>readFileSync(new URL('../../test/fixtures/console-vector-before-c03ah.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function restoreConsoleVector(source){
    source=restoreConsoleRetention(source,'core');
    assert.equal(hash(source),'71014cf14c2a46cd6ad1cf8c48fcfea3dd2d008e3fe61b6694c6d068162c5ffd','complete C03ah runtime core');
    source=source.replace('#include "../../shared/TLinkConsoleLogVectorIO.h"\n#include <sys/uio.h>\n#include <unistd.h>\n','');
    const h=source.indexOf('// BEGIN console vector capacity.'),e=source.indexOf('struct TLinkConsoleLogEntry {',h);assert.ok(h>=0&&e>h);source=source.slice(0,h)+source.slice(e);
    source=source.replace('- (BOOL)appendConsoleVectorBatch:(const std::vector<std::shared_ptr<TLinkConsoleLogEntry>> &)batch begin:(size_t)begin count:(size_t)count toConsolePath:(NSString *)path;\n','');
    const a=source.indexOf('- (BOOL)appendConsoleVectorBatch:',source.indexOf('- (void)prepareConsoleLogFiles {')),b=source.indexOf('- (void)drainConsoleLogs {',a);assert.ok(a>=0&&b>a);
    source=source.slice(0,a)+consoleVectorBefore()+source.slice(b);
    assert.equal(hash(source),'a68abd6179ef2134766bd7994f71a29968da56ec8c5ca58ad1cbc3d203168b12','complete preceding console/runtime source');return source;
}
