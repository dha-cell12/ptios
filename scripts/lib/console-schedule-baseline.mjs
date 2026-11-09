import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export const consoleScheduleSpecs=JSON.parse(readFileSync(new URL('./console-schedule-specs.json',import.meta.url),'utf8'));
export function restoreConsoleSchedule(source){
    if(!source.includes('TLinkConsoleDrainTicket.inc'))return source;
    const spec=consoleScheduleSpecs;assert.equal(hash(source),spec.currentHash,'complete root console transaction source');
    for(const part of [...spec.parts].reverse()){
        assert.equal(source.split(part.current).length,2,part.name);source=source.replace(part.current,part.before);
    }
    assert.equal(hash(source),spec.beforeHash,'complete preceding root console/authority/runtime');return source;
}
