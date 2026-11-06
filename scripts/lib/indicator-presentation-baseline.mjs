import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=source=>createHash('sha256').update(source).digest('hex');
export function indicatorBefore(){return readFileSync(new URL('../../test/fixtures/indicator-window-before-a02b.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
export function indicatorWindow(source){const start=source.indexOf('// BEGIN indicator presentation.');assert.ok(start>=0);return source.slice(start);}
export function checkIndicatorPresentation(source,helper,makefile){
    assert.equal(hash(source),'b3fb50e274d8f694b63905cc83230d6741c21d6b570b0720569cb9fe45e7c8c5','complete current indicator source');
    assert.equal(hash(helper),'7c3fe4fdf3ab0836152cb7ae021c813f631c194f2a1297842baf61684a2d8063','complete presentation core');
    let previous=source.replace(indicatorWindow(source),indicatorBefore());
    for(const include of ['#include "../../shared/TLinkIndicatorPresentation.h"\n','#import <QuartzCore/QuartzCore.h>\n']){
        assert.equal(previous.split(include).length-1,1);previous=previous.replace(include,'');
    }
    assert.equal(hash(previous),'50ce7b1ab56aaec28ef0d1a199cfb9c1745449d5a7ead8fcfd164ae5ee7ea614','complete preceding indicator lifecycle/callback/class');
    assert.equal((makefile.match(/CoreFoundation QuartzCore/g)||[]).length,1);
    assert.equal(hash(makefile.replace('CoreFoundation QuartzCore','CoreFoundation')),'30b5c2fbf7c97fbb9f302d59b8a4e8b1bc2d68456178a897af9253737735fd6c','complete preceding root makefile');
}
