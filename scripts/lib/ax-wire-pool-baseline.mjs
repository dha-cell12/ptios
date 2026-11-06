import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXWirePublishRoute} from './ax-wire-publish-baseline.mjs';
const specs={
  "root": {
    "start": "static void zx_uiTreeNotifyResult(",
    "end": "static BOOL zx_uiTreeContextChanged(",
    "handlerStart": "static void zx_handleUITreeTask(",
    "handlerEnd": "/**\nProcess Task",
    "hash": "cb2bf10a9b165cf6eca044bb13287aa300a1abcf5e70e82cf197c05a27e5ee2c",
    "edits": [
      [
        "    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";",
        "    NSString *base64 = nil;\n    @autoreleasepool {\n        base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n    }"
      ],
      [
        "    __attribute__((objc_precise_lifetime)) NSString *response = [NSString stringWithFormat:@\"0;;%@\\r\\n\", base64];",
        "    __attribute__((objc_precise_lifetime)) NSString *response = nil;\n    @autoreleasepool {\n        response = [NSString stringWithFormat:@\"0;;%@\\r\\n\", base64];\n    }"
      ],
      [
        "            NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";",
        "            NSString *base64 = nil;\n            @autoreleasepool {\n                base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n            }"
      ],
      [
        "            __attribute__((objc_precise_lifetime)) NSString *response = [NSString stringWithFormat:@\"0;;%@\\r\\n\", base64];",
        "            __attribute__((objc_precise_lifetime)) NSString *response = nil;\n            @autoreleasepool {\n                response = [NSString stringWithFormat:@\"0;;%@\\r\\n\", base64];\n            }"
      ]
    ]
  },
  "troll": {
    "start": "static NSData *TLinkUITreeJSONResponse(",
    "end": "static BOOL TLinkUITreeContextChanged(",
    "handlerStart": "static NSData *TLinkHandleUITreeTask(",
    "handlerEnd": "static NSData *TLinkHandleAppPaths(",
    "hash": "b8606f699a88770e72ff76d34ce51060eb05ead1b683c4c83527df0c59110ec8",
    "edits": [
      [
        "    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";",
        "    NSString *base64 = nil;\n    @autoreleasepool {\n        base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n    }"
      ],
      [
        "    NSData *response = TLinkSuccess(base64);",
        "    NSData *response = nil;\n    @autoreleasepool {\n        response = TLinkSuccess(base64);\n    }"
      ],
      [
        "        NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";",
        "        NSString *base64 = nil;\n        @autoreleasepool {\n            base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n        }"
      ],
      [
        "        NSData *response = TLinkSuccess(base64);",
        "        NSData *response = nil;\n        @autoreleasepool {\n            response = TLinkSuccess(base64);\n        }"
      ]
    ]
  }
};
const hash=s=>createHash('sha256').update(s).digest('hex');
export function wirePoolLegacy(name,kind){return readFileSync(new URL('../../test/fixtures/ax-wire-pool-'+name+'-'+kind+'-before-c05y.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
export function restoreAXWirePoolRoute(source,name){
    source=restoreAXWirePublishRoute(source,name);
    const p=specs[name];let restored=source;
    for(const [before,after] of p.edits){assert.equal(restored.split(after).length-1,1,'only base64/final construction pool and strong result transfer');restored=restored.replace(after,before);}
    for(const [kind,a,b] of [['response',p.start,p.end],['handler',p.handlerStart,p.handlerEnd]]){
        const first=restored.indexOf(a),last=restored.indexOf(b,first);assert.ok(first>=0&&last>first);
        assert.equal(restored.slice(first,last),wirePoolLegacy(name,kind),'complete preceding C05x '+name+' '+kind);
    }
    assert.equal(hash(restored),p.hash,'complete preceding C05x '+name+' source; unchanged gates/UTF8/notify/handlers');return restored;
}
