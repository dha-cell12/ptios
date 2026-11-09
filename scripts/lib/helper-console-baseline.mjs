import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const helperConsoleSpecs=JSON.parse(readFileSync(new URL('./helper-console-specs.json',import.meta.url),'utf8'));
const frozen=name=>readFileSync(new URL('../../test/fixtures/helper-console-'+name+'-before-c03ay.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export const helperConsoleBeforeHook=frozen('callback'),helperConsoleBeforeWriter=frozen('writer');
assert.equal(hash(helperConsoleBeforeHook),helperConsoleSpecs.beforeHookHash);
assert.equal(hash(helperConsoleBeforeWriter),helperConsoleSpecs.beforeWriterHash);
export function restoreHelperConsole(source){
    const spec=helperConsoleSpecs;if(!source.includes(spec.include))return source;
    assert.equal(hash(source),spec.currentHash,'complete bounded helper console source');
    for(const text of [spec.include,spec.writer,spec.hook])assert.equal(source.split(text).length,2);
    source=source.replace(spec.include,'').replace(spec.writer,'').replace(spec.hook,helperConsoleBeforeHook);
    assert.equal(hash(source),spec.beforeHash,'complete prior helper lifecycle/IO/authority/runtime');return source;
}
