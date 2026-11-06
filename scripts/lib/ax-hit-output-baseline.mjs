import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXWireCapability} from './ax-wire-baseline.mjs';
export const legacyAXHitOutput=readFileSync(new URL('../../test/fixtures/ax-hit-output-before-c05r.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');
const outputGate="            size_t rowBytes = 768;\n            for (NSString *key in @[@\"label\", @\"value\", @\"identifier\", @\"role\"]) {\n                NSString *text = element[key];\n                if (text.length > TLinkAXSnapshotOutput::MaxStringUTF8Bytes) {\n                    result = TLinkAXError(@\"ui_response_too_large\", @{@\"pid\": @(pid), @\"partial\": @YES});\n                    return;\n                }\n                size_t bytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];\n                if (!TLinkNativeOutputAllowed(bytes) || !TLinkAXSnapshotOutput::AddString(bytes, rowBytes)) {\n                    result = TLinkAXError(@\"ui_response_too_large\", @{@\"pid\": @(pid), @\"partial\": @YES});\n                    return;\n                }\n            }\n            size_t jsonBytes = 0, wireBytes = 0;\n            if (!TLinkAXSnapshotOutput::AppendRow(rowBytes, 0, jsonBytes, wireBytes) ||\n                !TLinkNativeOutputAllowed(wireBytes)) {\n                result = TLinkAXError(@\"ui_response_too_large\", @{@\"pid\": @(pid), @\"partial\": @YES});\n                return;\n            }\n";
const resultMarker="            result = @{\n                @\"ok\": @YES,\n                @\"schema\": @\"ui_hit_test_v1\",";
const capabilityField="        @\"max_hit_test_string_utf8_bytes\": @(TLinkAXSnapshotOutput::MaxStringUTF8Bytes),\n";
export function restoreAXHitOutput(source){
    source=restoreAXWireCapability(source);
    const a=source.indexOf('NSDictionary *TLinkAXElementAtPoint(');assert.ok(a>=0);
    assert.equal(source.slice(a),legacyAXHitOutput.replace(resultMarker,outputGate+resultMarker),
        'only post-cleanup hit result output admission; queries/serializer/CF/stop/deadline/metadata/authority remain');
    let restored=source.slice(0,a)+legacyAXHitOutput;
    assert.equal(restored.split(capabilityField).length-1,1);restored=restored.replace(capabilityField,'');
    assert.equal(createHash('sha256').update(restored).digest('hex'),'69428e714afbd8898aebc9192fdd35dcbde75d454a9ef6ff1bd8205cf5d52227','complete preceding C05q AX source');
    return restored;
}
