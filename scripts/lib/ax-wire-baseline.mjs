import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXBoundedJSONRoute,restoreAXJSONCapability} from './ax-bounded-json-baseline.mjs';
const specs={"root": {"file": "pccontrol/Task.xm", "start": "static void zx_uiTreeNotifyResult(", "end": "static BOOL zx_uiTreeContextChanged(", "handlerStart": "static void zx_handleUITreeTask(", "handlerEnd": "/**\nProcess Task", "includes": "#include \"../shared/TLinkAXWireOutput.h\"\n#include \"../shared/TLinkNativeBudget.h\"\n", "hash": "55cc46a2dc7b02c55bc05e776262acc9e806cdf420bb06935ca2bc0a2dcfd6e2", "responseOld": "    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";", "responseNew": "    size_t wireBytes = 0;\n    if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {\n        notifyClient((UInt8 *)\"-1;;ui_response_too_large\\r\\n\", stream);\n        return;\n    }\n    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";", "handlerOld": "            NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";", "handlerNew": "            size_t wireBytes = 0;\n            if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {\n                notifyClient((UInt8 *)\"-1;;ui_response_too_large\\r\\n\", stream);\n                return;\n            }\n            NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";"}, "troll": {"file": "stream-app/streamd/POCSocketServer.mm", "start": "static NSData *TLinkUITreeJSONResponse(", "end": "static BOOL TLinkUITreeContextChanged(", "handlerStart": "static NSData *TLinkHandleUITreeTask(", "handlerEnd": "static NSData *TLinkHandleAppPaths(", "includes": "#include \"../../shared/TLinkAXWireOutput.h\"\n#include \"../../shared/TLinkNativeBudget.h\"\n", "hash": "1e70e824c8f0730f26c9385f41318e8aa7c0b1813138c046bba724e471ed1e9d", "responseOld": "    return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @\"\");", "responseNew": "    size_t wireBytes = 0;\n    if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {\n        return TLinkError(@\"ui_response_too_large\");\n    }\n    return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @\"\");", "handlerOld": "        return json.length > 0\n            ? TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @\"\")\n            : TLinkError(@\"ui_capability_json_failed\");", "handlerNew": "        if (json.length == 0) return TLinkError(@\"ui_capability_json_failed\");\n        size_t wireBytes = 0;\n        if (!TLinkAXWireOutput::SuccessSize(json.length, wireBytes) || !TLinkNativeOutputAllowed(wireBytes)) {\n            return TLinkError(@\"ui_response_too_large\");\n        }\n        return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @\"\");"}};
const hash=s=>createHash('sha256').update(s).digest('hex');
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8').replaceAll('\r\n','\n');
export function wireRegion(source,start,end){const a=source.indexOf(start),b=source.indexOf(end,a);assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function wireLegacy(name,kind){return read('test/fixtures/ax-wire-'+name+'-'+kind+'-before-c05s.inc');}
export function wireResponse(source,name){const p=specs[name];return wireRegion(source,p.start,p.end);}
export function wireHandler(source,name){const p=specs[name];return wireRegion(source,p.handlerStart,p.handlerEnd);}
export function wireCapability(handler){const a=handler.indexOf('    if (taskType == '),b=handler.indexOf('    NSString *decodeError',a);assert.ok(a>=0&&b>a);return handler.slice(a,b);}
export function restoreAXWireRoute(source,name){
    source=restoreAXBoundedJSONRoute(source,name);
    const p=specs[name],response=wireResponse(source,name),handler=wireHandler(source,name);
    const beforeResponse=wireLegacy(name,'response'),beforeHandler=wireLegacy(name,'handler');
    assert.equal(response,beforeResponse.replace(p.responseOld,p.responseNew),'only pre-base64 result size/output admission');
    assert.equal(handler,beforeHandler.replace(p.handlerOld,p.handlerNew),'only pre-base64 capability size/output admission; request/foreground/tap/authority unchanged');
    assert.equal(source.split(p.includes).length-1,1);
    const restored=source.replace(p.includes,'').replace(response,beforeResponse).replace(handler,beforeHandler);
    assert.equal(hash(restored),p.hash,'complete preceding C05r '+name+' task/server source');return restored;
}
export function restoreAXWireCapability(source){
    source=restoreAXJSONCapability(source);
    const inc="#include \"TLinkAXWireOutput.h\"\n",field="        @\"hard_max_success_wire_bytes\": @(TLinkAXWireOutput::MaxSuccessWireBytes),\n";
    for(const text of [inc,field]){assert.equal(source.split(text).length-1,1);source=source.replace(text,'');}
    assert.equal(hash(source),'9994ec5981b9546114d61be37f2f6bda369d910ea2b59d610b0360e28d16e4e1','complete preceding C05r AX source');return source;
}
