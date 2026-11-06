import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXCapabilityPreflightRoute} from './ax-capability-preflight-baseline.mjs';
const spec={
  "start": "static void zx_uiTreeNotifyResult(",
  "end": "static BOOL zx_uiTreeContextChanged(",
  "handlerStart": "static void zx_handleUITreeTask(",
  "handlerEnd": "/**\nProcess Task",
  "hash": "350b037cd6f8af43ebea83dbdba30caefecc76b9eb2b4444abe2817a7625b2c5",
  "trollHash": "1b4cc710cdb850857e1d5d7cfe7112e18173ca8096254522ea418f0a79841636",
  "edits": [
    [
      "    const char *responseBytes = response.UTF8String;\n    admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n    if (admission != TLinkAXWireBudget::Admission::Ready) {\n        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);\n        return;\n    }\n    notifyClient((UInt8 *)responseBytes, stream);",
      "    @autoreleasepool {\n        const char *responseBytes = response.UTF8String;\n        admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n        if (admission != TLinkAXWireBudget::Admission::Ready) {\n            notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);\n            return;\n        }\n        notifyClient((UInt8 *)responseBytes, stream);\n    }"
    ],
    [
      "            const char *responseBytes = response.UTF8String;\n            admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n            if (admission != TLinkAXWireBudget::Admission::Ready) {\n                notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);\n                return;\n            }\n            notifyClient((UInt8 *)responseBytes, stream);",
      "            @autoreleasepool {\n                const char *responseBytes = response.UTF8String;\n                admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n                if (admission != TLinkAXWireBudget::Admission::Ready) {\n                    notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);\n                    return;\n                }\n                notifyClient((UInt8 *)responseBytes, stream);\n            }"
    ]
  ]
};
const hash=s=>createHash('sha256').update(s).digest('hex');
export function wirePublishLegacy(kind){return readFileSync(new URL('../../test/fixtures/ax-wire-publish-root-'+kind+'-before-c05z.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
export function restoreAXWirePublishRoute(source,name){
    source=restoreAXCapabilityPreflightRoute(source,name);
    if(name==='troll'){assert.equal(hash(source),spec.trollHash,'complete unchanged C05y TrollStore server');return source;}
    assert.equal(name,'root');let restored=source;
    for(const [before,after] of spec.edits){assert.equal(restored.split(after).length-1,1,'only UTF8/check/synchronous notify pool');restored=restored.replace(after,before);}
    for(const [kind,a,b] of [['response',spec.start,spec.end],['handler',spec.handlerStart,spec.handlerEnd]]){
        const first=restored.indexOf(a),last=restored.indexOf(b,first);assert.ok(first>=0&&last>first);
        assert.equal(restored.slice(first,last),wirePublishLegacy(kind),'complete preceding C05y root '+kind);
    }
    assert.equal(hash(restored),spec.hash,'complete preceding C05y root task; unchanged gates/bytes/ordering');return restored;
}
