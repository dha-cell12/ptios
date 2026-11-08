import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8').replaceAll('\r\n','\n');
const specs=JSON.parse(readFileSync(new URL('./persistence-json-specs.json',import.meta.url),'utf8'));
export function restorePersistenceJSON(source,kind){
    const spec=specs[kind];
    if(!source.includes(spec.include.trimEnd()))return source;
    assert.equal(hash(source),spec.currentHash,'complete C03aq '+kind);
    const a=source.indexOf(spec.start),b=source.indexOf(spec.end,a+spec.start.length);
    assert.ok(a>=0&&b>a);assert.equal(hash(source.slice(a,b)),spec.partHash,kind+' writer');
    source=(source.slice(0,a)+read('test/fixtures/persistence-json-'+kind+'-before-c03aq.inc')+source.slice(b)).replace(spec.include,'');
    assert.equal(hash(source),spec.beforeHash,'complete preceding '+kind);return source;
}
export function restorePersistenceJSONMakefile(source,file){
    if(!source.includes('TLinkPersistenceJSON.mm'))return source;
    const spec=specs.makefiles[file];assert.ok(spec,file);
    assert.equal(hash(source),spec.currentHash,'complete C03aq '+file);
    assert.equal(source.split(spec.token).length-1,spec.count);
    source=source.replaceAll(spec.token,'');
    assert.equal(hash(source),spec.beforeHash,'complete preceding '+file);return source;
}
export function checkPersistenceJSON(){
    for(const [file,key] of [['TLinkPersistenceJSONQuota.h','quotaHash'],['TLinkPersistenceJSON.h','headerHash'],['TLinkPersistenceJSON.mm','implementationHash']])
        assert.equal(hash(read('shared/'+file)),specs[key],file+' complete source');
    for(const [file,targets] of [['pccontrol/Makefile',['pccontrol']],['tlinkauto-binary/Makefile',['tlinkautod','tlinkautob']],['stream-app/streamd/Makefile',['streamd']]]){
        const source=read(file);restorePersistenceJSONMakefile(source,file);
        for(const target of targets){
            const line=source.split('\n').find(s=>s.startsWith(target+'_FILES ='));
            assert.ok(line,target);assert.equal((line.match(/TLinkPersistenceJSON\.mm/g)||[]).length,1,target+' links one JSON stream');
        }
    }
}
