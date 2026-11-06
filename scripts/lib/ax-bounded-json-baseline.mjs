import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const specs={"root": {"file": "pccontrol/Task.xm", "start": "static void zx_uiTreeNotifyResult(", "end": "static BOOL zx_uiTreeContextChanged(", "handlerStart": "static void zx_handleUITreeTask(", "handlerEnd": "/**\nProcess Task", "include": "#import \"../shared/TLinkAXJSONOutput.h\"\n", "hash": "4836cbf60c9106d760a1e65cc315743202cb1eb585e2bdadfdd2cfe401a24c9c", "responseOld": "    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];\n", "responseNew": "    BOOL jsonTooLarge = false;\n    NSData *json = TLinkAXBoundedJSONData(result, &jsonTooLarge);\n    if (jsonTooLarge) {\n        notifyClient((UInt8 *)\"-1;;ui_response_too_large\\r\\n\", stream);\n        return;\n    }\n", "handlerOld": "        NSData *json = [NSJSONSerialization dataWithJSONObject:capability options:0 error:nil];\n", "handlerNew": "        BOOL jsonTooLarge = false;\n        NSData *json = TLinkAXBoundedJSONData(capability, &jsonTooLarge);\n        if (jsonTooLarge) {\n            notifyClient((UInt8 *)\"-1;;ui_response_too_large\\r\\n\", stream);\n            return;\n        }\n"}, "troll": {"file": "stream-app/streamd/POCSocketServer.mm", "start": "static NSData *TLinkUITreeJSONResponse(", "end": "static BOOL TLinkUITreeContextChanged(", "handlerStart": "static NSData *TLinkHandleUITreeTask(", "handlerEnd": "static NSData *TLinkHandleAppPaths(", "include": "#import \"../../shared/TLinkAXJSONOutput.h\"\n", "hash": "2f9cc1ba94499d7a33dafc5f3c618d7a9b059e78f59a350ed7b6592c9ea24a03", "responseOld": "    NSError *error = nil;\n    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:&error];\n", "responseNew": "    BOOL jsonTooLarge = false;\n    NSData *json = TLinkAXBoundedJSONData(result, &jsonTooLarge);\n    if (jsonTooLarge) {\n        return TLinkError(@\"ui_response_too_large\");\n    }\n", "handlerOld": "        NSError *jsonError = nil;\n        NSData *json = [NSJSONSerialization dataWithJSONObject:capability options:0 error:&jsonError];\n", "handlerNew": "        BOOL jsonTooLarge = false;\n        NSData *json = TLinkAXBoundedJSONData(capability, &jsonTooLarge);\n        if (jsonTooLarge) {\n            return TLinkError(@\"ui_response_too_large\");\n        }\n"}};
const hash=s=>createHash('sha256').update(s).digest('hex');
export function boundedJSONLegacy(name,kind){return readFileSync(new URL('../../test/fixtures/ax-bounded-json-'+name+'-'+kind+'-before-c05t.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
export function restoreAXBoundedJSONRoute(source,name){
    const p=specs[name];
    const a=source.indexOf(p.start),b=source.indexOf(p.end,a),c=source.indexOf(p.handlerStart),d=source.indexOf(p.handlerEnd,c);assert.ok(a>=0&&b>a&&c>b&&d>c);
    const response=source.slice(a,b),handler=source.slice(c,d),r=boundedJSONLegacy(name,'response'),h=boundedJSONLegacy(name,'handler');
    assert.equal(response,r.replace(p.responseOld,p.responseNew),'only bounded JSON writer and explicit size rejection; final wire/failed results unchanged');
    assert.equal(handler,h.replace(p.handlerOld,p.handlerNew),'only capability serializer; rest of requests/action/authority source unchanged');
    assert.equal(source.split(p.include).length-1,1);
    const restored=source.replace(p.include,'').replace(response,r).replace(handler,h);
    assert.equal(hash(restored),p.hash,'complete preceding C05s '+name+' task/server source');return restored;
}
export function restoreAXJSONCapability(source){
    for(const part of ['#include "TLinkAXJSONQuota.h"\n','        @"hard_max_json_bytes": @(TLinkAXJSONOutput::MaxJSONBytes),\n']){assert.equal(source.split(part).length-1,1);source=source.replace(part,'');}
    assert.equal(hash(source),'290cc97388800e238a9106fe12d0a2597690363462767b93372db2e1d7c832d2','complete preceding C05s AX source');return source;
}
