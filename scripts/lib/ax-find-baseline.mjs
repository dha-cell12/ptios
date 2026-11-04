import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAXFind=readFileSync(new URL('../../test/fixtures/ax-find-before-c05e.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
export function axFind(source){const a=source.indexOf('static NSDictionary *TLinkAXFindInSnapshot('),b=source.indexOf('NSDictionary *TLinkAXFindElement(',a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restoreAXFind(source){
    const expected=legacyAXFind
        .replace('    NSMutableArray *matches = [NSMutableArray array];','    NSUInteger matchCount = 0;\n    NSDictionary *selectedElement = nil;')
        .replace('        [matches addObject:element];','        if (matchCount == (NSUInteger)requestedIndex) selectedElement = element;\n        ++matchCount;')
        .replace('    NSDictionary *element = requestedIndex < (NSInteger)matches.count ? matches[(NSUInteger)requestedIndex] : nil;','    NSDictionary *element = selectedElement;')
        .replace('    result[@"match_count"] = @(matches.count);','    result[@"match_count"] = @(matchCount);');
    assert.equal(axFind(source),expected,'only match-array removal; full matcher/filter/order/normalization/cancellation/result source preserved');
    const restored=source.replace(axFind(source),legacyAXFind);
    assert.equal(createHash('sha256').update(restored).digest('hex'),'e2e49725678971259e4b5469dc7f2e2f70fc4f88c84ca7f68cf4c7df765e9852',
        'complete preceding C05d AX, scan/attribute/CF/capability/foreground/action and authority contract');
    return restored;
}
