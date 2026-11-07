import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=source=>createHash('sha256').update(source).digest('hex');
export function filePayloadBefore(){return readFileSync(new URL('../../test/fixtures/file-handle-before-c03ac.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
const part=(text,start,end)=>{const a=text.indexOf(start),b=text.indexOf(end,a+start.length);assert.ok(a>=0&&b>a);return text.slice(a,b);};
export function restoreFilePayload(source){
    assert.equal(hash(source),'7b263e026e99f64a21f26b6958ef07e0896e91cd9d6220d75d461b1f9ae4774d','complete current FileHandle payload source');
    const before=filePayloadBefore();
    for(const include of ['#include "TLinkJSFileIO.h"\n','#include "TLinkUTF8Data.h"\n']){assert.equal(source.split(include).length-1,1);source=source.replace(include,'');}
    for(const [start,end] of [['readRequest:','readLine'],['readLine','writeData:'],['writeData:','writeText:'],['writeText:','writeBase64:'],['writeBase64:','seekWhence:']]){
        const a='- (NSDictionary *)'+start,b='- (NSDictionary *)'+end;
        source=source.replace(part(source,a,b),part(before,a,b));
    }
    assert.equal(hash(source),'88d9e029f7fef337134890b97296b67568cb27c457016776874f904de510d9b9','complete preceding FileHandle class/JS/descriptor policy');return source;
}
export function checkFileIOHeader(source){assert.equal(hash(source),'b6dd07eb203441ac04a67f0229868f55409a1b118e39914dde2f2041861b2908','complete checked file IO helper');}
