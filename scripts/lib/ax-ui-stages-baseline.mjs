import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const tasks={
  "root": {
    "start": "static void zx_handleUITreeTask(",
    "end": "/**\nProcess Task",
    "hash": "4162062dc6f07a406e0db0193306ae5b18489743d74b164c1e7f646b4bbe992d",
    "edits": [
      [
        "    NSString *decodeError = nil;\n",
        "    NSString *decodeError = nil;\n    const auto uiBudget = TLinkCurrentNativeBudget();\n"
      ],
      [
        "    NSDictionary *context = TLinkAXCopyFrontmostContext();\n",
        "    auto uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(uiStop), stream);\n        return;\n    }\n    NSDictionary *context = TLinkAXCopyFrontmostContext();\n"
      ],
      [
        "    NSString *bundleID = context[@\"bundle_id\"];\n",
        "    uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(uiStop), stream);\n        return;\n    }\n    NSString *bundleID = context[@\"bundle_id\"];\n"
      ],
      [
        "    if (zx_uiTreeContextChanged(context)) {\n",
        "    uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(uiStop), stream);\n        return;\n    }\n    if (zx_uiTreeContextChanged(context)) {\n"
      ],
      [
        "    NSMutableDictionary *finalResult = [result mutableCopy];\n",
        "    uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(uiStop), stream);\n        return;\n    }\n    NSMutableDictionary *finalResult = [result mutableCopy];\n"
      ],
      [
        "        NSDictionary *point = element[@\"activation_point\"];\n",
        "        uiStop = TLinkAXWireBudget::Stop(uiBudget);\n        if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n            notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(uiStop), stream);\n            return;\n        }\n        NSDictionary *point = element[@\"activation_point\"];\n"
      ],
      [
        "        NSError *tapError = nil;\n",
        "        uiStop = TLinkAXWireBudget::Stop(uiBudget);\n        if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n            notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(uiStop), stream);\n            return;\n        }\n        NSError *tapError = nil;\n"
      ],
      [
        "    zx_uiTreeNotifyResult(finalResult, stream);\n",
        "    uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(uiStop), stream);\n        return;\n    }\n    zx_uiTreeNotifyResult(finalResult, stream);\n"
      ]
    ]
  },
  "troll": {
    "start": "static NSData *TLinkHandleUITreeTask(",
    "end": "static NSData *TLinkHandleAppPaths(",
    "hash": "b16a4f3008fea3ffdab8674b27e5fd7ec28d213ac7d5445562e156f90b1b9daf",
    "edits": [
      [
        "    NSString *decodeError = nil;\n",
        "    NSString *decodeError = nil;\n    const auto uiBudget = TLinkCurrentNativeBudget();\n"
      ],
      [
        "    NSDictionary *context = TLinkUITreeFrontmostContext();\n",
        "    auto uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n            ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n    }\n    NSDictionary *context = TLinkUITreeFrontmostContext();\n"
      ],
      [
        "    NSString *bundleId = context[@\"bundle_id\"];\n",
        "    uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n            ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n    }\n    NSString *bundleId = context[@\"bundle_id\"];\n"
      ],
      [
        "        if (taskType == 78) {\n",
        "        uiStop = TLinkAXWireBudget::Stop(uiBudget);\n        if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        if (taskType == 78) {\n"
      ],
      [
        "        // The app may have changed between the context probe and the real\n",
        "        uiStop = TLinkAXWireBudget::Stop(uiBudget);\n        if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        // The app may have changed between the context probe and the real\n"
      ],
      [
        "        NSDictionary *retryContext = TLinkUITreeFrontmostContext();\n",
        "        uiStop = TLinkAXWireBudget::Stop(uiBudget);\n        if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        NSDictionary *retryContext = TLinkUITreeFrontmostContext();\n"
      ],
      [
        "        context = retryContext;\n",
        "        uiStop = TLinkAXWireBudget::Stop(uiBudget);\n        if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        context = retryContext;\n"
      ],
      [
        "    BOOL changed = TLinkUITreeContextChanged(context);\n",
        "    uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n            ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n    }\n    BOOL changed = TLinkUITreeContextChanged(context);\n"
      ],
      [
        "    if (taskType == 81) {\n        NSDictionary *element",
        "    uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n            ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n    }\n    if (taskType == 81) {\n        NSDictionary *element"
      ],
      [
        "        NSDictionary *point = [element[@\"activation_point\"] isKindOfClass:[NSDictionary class]]\n",
        "        uiStop = TLinkAXWireBudget::Stop(uiBudget);\n        if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        NSDictionary *point = [element[@\"activation_point\"] isKindOfClass:[NSDictionary class]]\n"
      ],
      [
        "        NSString *tapError = nil;\n",
        "        uiStop = TLinkAXWireBudget::Stop(uiBudget);\n        if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        NSString *tapError = nil;\n"
      ],
      [
        "    return TLinkUITreeJSONResponse(finalResult);\n",
        "    uiStop = TLinkAXWireBudget::Stop(uiBudget);\n    if (uiStop != TLinkAXWireBudget::Admission::Ready) {\n        return TLinkError(uiStop == TLinkAXWireBudget::Admission::Stopped\n            ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n    }\n    return TLinkUITreeJSONResponse(finalResult);\n"
      ]
    ]
  }
};
const find={
  "start": "static NSDictionary *TLinkAXFindInSnapshot(",
  "end": "BOOL TLinkAXResultCompleteForAction(",
  "hash": "0317e46b62b6f1ddee149f0af2b876d349b415d0a2cc20c8ddc721e1f5015295",
  "edits": [
    [
      "            if (role.length > 0 &&\n",
      "            if (TLinkNativeStopped()) return TLinkAXError(@\"ui_cancelled_or_timed_out\", @{@\"partial\": @YES});\n            if (role.length > 0 &&\n"
    ],
    [
      "            if (text.length > 0) {\n",
      "            if (TLinkNativeStopped()) return TLinkAXError(@\"ui_cancelled_or_timed_out\", @{@\"partial\": @YES});\n            if (text.length > 0) {\n"
    ],
    [
      "                BOOL valueMatch = TLinkAXTextMatches(element[@\"value\"], text, mode, caseSensitive);\n",
      "                if (TLinkNativeStopped()) return TLinkAXError(@\"ui_cancelled_or_timed_out\", @{@\"partial\": @YES});\n                BOOL valueMatch = TLinkAXTextMatches(element[@\"value\"], text, mode, caseSensitive);\n                if (TLinkNativeStopped()) return TLinkAXError(@\"ui_cancelled_or_timed_out\", @{@\"partial\": @YES});\n"
    ],
    [
      "            if (matchCount == (NSUInteger)requestedIndex) selectedElement = element;\n",
      "            if (TLinkNativeStopped()) return TLinkAXError(@\"ui_cancelled_or_timed_out\", @{@\"partial\": @YES});\n            if (matchCount == (NSUInteger)requestedIndex) selectedElement = element;\n"
    ],
    [
      "    return result;\n",
      "    if (TLinkNativeStopped()) return TLinkAXError(@\"ui_cancelled_or_timed_out\", @{@\"partial\": @YES});\n    return result;\n"
    ],
    [
      "    __block NSDictionary *result = nil;\n",
      "    if (TLinkNativeStopped()) return TLinkAXError(@\"ui_cancelled_or_timed_out\", @{@\"partial\": @YES});\n    __block NSDictionary *result = nil;\n"
    ]
  ]
};
const hash=s=>createHash('sha256').update(s).digest('hex');
const read=p=>readFileSync(new URL('../../test/fixtures/'+p,import.meta.url),'utf8').replaceAll('\r\n','\n');
export const legacyUIStagesFind=read('ax-ui-stages-find-before-c05ab.inc');
export function uiStagesLegacy(name){return read('ax-ui-stages-'+name+'-handler-before-c05ab.inc');}
function restore(source,p,legacy){
 const a=source.indexOf(p.start),b=source.indexOf(p.end,a);assert.ok(a>=0&&b>a);let expected=legacy;
 for(const [before,after] of p.edits){const at=expected.indexOf(before);assert.ok(at>=0);const positions=[];let pos=at;while(pos>=0){if(pos===0||expected[pos-1]==='\n')positions.push(pos);pos=expected.indexOf(before,pos+1);}assert.equal(positions.length,1);expected=expected.slice(0,positions[0])+after+expected.slice(positions[0]+before.length);}
 assert.equal(source.slice(a,b),expected,'only cooperative stage cancellation, all reached errors/guards/authority/action/query source retained');
 const restored=source.slice(0,a)+legacy+source.slice(b);assert.equal(hash(restored),p.hash,'complete preceding C05aa source');return restored;
}
export function restoreUIStagesTask(source,name){return restore(source,tasks[name],uiStagesLegacy(name));}
export function restoreUIStagesFind(source){return restore(source,find,legacyUIStagesFind);}
