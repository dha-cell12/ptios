import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {restoreAXWirePoolRoute} from './ax-wire-pool-baseline.mjs';
const specs={
  "root": {
    "file": "pccontrol/Task.xm",
    "start": "static void zx_uiTreeNotifyResult(",
    "end": "static BOOL zx_uiTreeContextChanged(",
    "handlerStart": "static void zx_handleUITreeTask(",
    "handlerEnd": "/**\nProcess Task",
    "include": "#include \"../shared/TLinkAXWireBudget.h\"\n",
    "hash": "ce485a740863e47592d1cca95ded88d09249bd02b512aa1722786dcac7da1ba9",
    "edits": [
      [
        "    BOOL jsonTooLarge = false, jsonStopped = false;\n",
        "    const auto wireBudget = TLinkCurrentNativeBudget();\n    BOOL jsonTooLarge = false, jsonStopped = false;\n"
      ],
      [
        "    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n    notifyClient((UInt8 *)[[NSString stringWithFormat:@\"0;;%@\\r\\n\", base64] UTF8String], stream);",
        "    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n    auto admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n    if (admission != TLinkAXWireBudget::Admission::Ready) {\n        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);\n        return;\n    }\n    __attribute__((objc_precise_lifetime)) NSString *response = [NSString stringWithFormat:@\"0;;%@\\r\\n\", base64];\n    const char *responseBytes = response.UTF8String;\n    admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n    if (admission != TLinkAXWireBudget::Admission::Ready) {\n        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);\n        return;\n    }\n    notifyClient((UInt8 *)responseBytes, stream);"
      ],
      [
        "        BOOL jsonTooLarge = false, jsonStopped = false;\n",
        "        const auto wireBudget = TLinkCurrentNativeBudget();\n        BOOL jsonTooLarge = false, jsonStopped = false;\n"
      ],
      [
        "            NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n            notifyClient((UInt8 *)[[NSString stringWithFormat:@\"0;;%@\\r\\n\", base64] UTF8String], stream);",
        "            NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n            auto admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n            if (admission != TLinkAXWireBudget::Admission::Ready) {\n                notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);\n                return;\n            }\n            __attribute__((objc_precise_lifetime)) NSString *response = [NSString stringWithFormat:@\"0;;%@\\r\\n\", base64];\n            const char *responseBytes = response.UTF8String;\n            admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n            if (admission != TLinkAXWireBudget::Admission::Ready) {\n                notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(admission), stream);\n                return;\n            }\n            notifyClient((UInt8 *)responseBytes, stream);"
      ]
    ]
  },
  "troll": {
    "file": "stream-app/streamd/POCSocketServer.mm",
    "start": "static NSData *TLinkUITreeJSONResponse(",
    "end": "static BOOL TLinkUITreeContextChanged(",
    "handlerStart": "static NSData *TLinkHandleUITreeTask(",
    "handlerEnd": "static NSData *TLinkHandleAppPaths(",
    "include": "#include \"../../shared/TLinkAXWireBudget.h\"\n",
    "hash": "b36c6ea00e4ceca3ed6e39eadc8211982505f2b076e102b2f972fa56dcb04126",
    "edits": [
      [
        "    BOOL jsonTooLarge = false, jsonStopped = false;\n",
        "    const auto wireBudget = TLinkCurrentNativeBudget();\n    BOOL jsonTooLarge = false, jsonStopped = false;\n"
      ],
      [
        "    return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @\"\");",
        "    NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n    auto admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n    if (admission != TLinkAXWireBudget::Admission::Ready) {\n        return TLinkError(admission == TLinkAXWireBudget::Admission::Stopped\n            ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n    }\n    NSData *response = TLinkSuccess(base64);\n    admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n    if (admission != TLinkAXWireBudget::Admission::Ready) {\n        return TLinkError(admission == TLinkAXWireBudget::Admission::Stopped\n            ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n    }\n    return response;"
      ],
      [
        "        BOOL jsonTooLarge = false, jsonStopped = false;\n",
        "        const auto wireBudget = TLinkCurrentNativeBudget();\n        BOOL jsonTooLarge = false, jsonStopped = false;\n"
      ],
      [
        "        return TLinkSuccess([json base64EncodedStringWithOptions:0] ?: @\"\");",
        "        NSString *base64 = [json base64EncodedStringWithOptions:0] ?: @\"\";\n        auto admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n        if (admission != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(admission == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        NSData *response = TLinkSuccess(base64);\n        admission = TLinkAXWireBudget::Check(wireBudget, wireBytes);\n        if (admission != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(admission == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        return response;"
      ]
    ]
  }
};
const hash=s=>createHash('sha256').update(s).digest('hex');
export function wireBudgetLegacy(name,kind){return readFileSync(new URL('../../test/fixtures/ax-wire-budget-'+name+'-'+kind+'-before-c05x.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
export function restoreAXWireBudgetRoute(source,name){
    source=restoreAXWirePoolRoute(source,name);
    const p=specs[name];assert.equal(source.split(p.include).length-1,1);
    let restored=source.replace(p.include,'');
    for(const [before,after] of p.edits){assert.equal(restored.split(after).length-1,1,'complete current codec/handler region');restored=restored.replace(after,before);}
    for(const [kind,a,b] of [['response',p.start,p.end],['handler',p.handlerStart,p.handlerEnd]]){
        const first=restored.indexOf(a),last=restored.indexOf(b,first);assert.ok(first>=0&&last>first);
        assert.equal(restored.slice(first,last),wireBudgetLegacy(name,kind),'complete preceding C05w '+name+' '+kind);
    }
    assert.equal(hash(restored),p.hash,'complete preceding C05w '+name+' source; only captured post-base64/final-wire admission');return restored;
}
