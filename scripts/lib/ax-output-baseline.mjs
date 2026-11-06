import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const legacyAXOutput=readFileSync(new URL('../../test/fixtures/ax-output-before-c05q.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
const oldAccounting="                size_t bytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];\n                if (!TLinkNativeOutputAllowed(bytes)) return TLinkAXError(@\"ui_response_too_large\", @{@\"partial\": @YES});\n                rowBytes += 6 * bytes;\n            }\n            estimatedJSONBytes += rowBytes;\n            if (!TLinkNativeOutputAllowed(32 * 1024 + 4 * ((estimatedJSONBytes + 2) / 3)))";
const newAccounting="                if (text.length > TLinkAXSnapshotOutput::MaxStringUTF8Bytes)\n                    return TLinkAXError(@\"ui_response_too_large\", @{@\"partial\": @YES});\n                size_t bytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];\n                if (!TLinkNativeOutputAllowed(bytes) || !TLinkAXSnapshotOutput::AddString(bytes, rowBytes))\n                    return TLinkAXError(@\"ui_response_too_large\", @{@\"partial\": @YES});\n            }\n            size_t nextJSONBytes = 0, wireBytes = 0;\n            if (!TLinkAXSnapshotOutput::AppendRow(rowBytes, estimatedJSONBytes, nextJSONBytes, wireBytes) ||\n                !TLinkNativeOutputAllowed(wireBytes))";
export function restoreAXOutput(source){
    const a=source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('),b=source.indexOf('NSDictionary *TLinkAXCopySnapshot(pid_t',a);assert.ok(a>=0&&b>a);
    const expected=legacyAXOutput.replace(oldAccounting,newAccounting).replace('            [rows addObject:node];','            estimatedJSONBytes = nextJSONBytes;\n            [rows addObject:node];');
    assert.equal(source.slice(a,b),expected,'only per-string preflight/UTF8 cap and checked existing JSON/wire accounting; gates/rows/order/CF/deadlines/authority preserved');
    let restored=source.slice(0,a)+legacyAXOutput+source.slice(b);
    for(const part of ['#include "TLinkAXSnapshotOutput.h"\n','        @"max_snapshot_string_utf8_bytes": @(TLinkAXSnapshotOutput::MaxStringUTF8Bytes),\n']){
        assert.equal(restored.split(part).length-1,1);restored=restored.replace(part,'');
    }
    assert.equal(createHash('sha256').update(restored).digest('hex'),'8084f19bd1f27778e23f3342c4b3ded099ca768d221104a5a2cd0a6a857d68cf','complete preceding C05p AX source');
    return restored;
}
