import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const specs={
  "root": {
    "file": "pccontrol/Task.xm",
    "start": "static void zx_handleUITreeTask(",
    "end": "/**\nProcess Task",
    "hash": "6626d8063dc40511552ae753cc8f54b1bac200f303c7356b82e7fd2844100b31",
    "edits": [
      [
        "        const auto wireBudget = TLinkCurrentNativeBudget();\n",
        ""
      ],
      [
        "        NSMutableDictionary *capability = [TLinkAXCapabilitySnapshot() mutableCopy];\n",
        "        const auto wireBudget = TLinkCurrentNativeBudget();\n        auto capabilityStop = TLinkAXWireBudget::Stop(wireBudget);\n        if (capabilityStop != TLinkAXWireBudget::Admission::Ready) {\n            notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(capabilityStop), stream);\n            return;\n        }\n        NSMutableDictionary *capability = [TLinkAXCapabilitySnapshot() mutableCopy];\n        capabilityStop = TLinkAXWireBudget::Stop(wireBudget);\n        if (capabilityStop != TLinkAXWireBudget::Admission::Ready) {\n            notifyClient((UInt8 *)TLinkAXWireBudget::FailureWire(capabilityStop), stream);\n            return;\n        }\n"
      ]
    ]
  },
  "troll": {
    "file": "stream-app/streamd/POCSocketServer.mm",
    "start": "static NSData *TLinkHandleUITreeTask(",
    "end": "static NSData *TLinkHandleAppPaths(",
    "hash": "1b4cc710cdb850857e1d5d7cfe7112e18173ca8096254522ea418f0a79841636",
    "edits": [
      [
        "        const auto wireBudget = TLinkCurrentNativeBudget();\n",
        ""
      ],
      [
        "        NSMutableDictionary *capability = [TLinkAXCapabilitySnapshot() mutableCopy];\n",
        "        const auto wireBudget = TLinkCurrentNativeBudget();\n        auto capabilityStop = TLinkAXWireBudget::Stop(wireBudget);\n        if (capabilityStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(capabilityStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n        NSMutableDictionary *capability = [TLinkAXCapabilitySnapshot() mutableCopy];\n        capabilityStop = TLinkAXWireBudget::Stop(wireBudget);\n        if (capabilityStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(capabilityStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n"
      ],
      [
        "        NSDictionary *foreground = TLinkUITreeFrontmostContext();\n",
        "        NSDictionary *foreground = TLinkUITreeFrontmostContext();\n        capabilityStop = TLinkAXWireBudget::Stop(wireBudget);\n        if (capabilityStop != TLinkAXWireBudget::Admission::Ready) {\n            return TLinkError(capabilityStop == TLinkAXWireBudget::Admission::Stopped\n                ? @\"ui_cancelled_or_timed_out\" : @\"ui_response_too_large\");\n        }\n"
      ]
    ]
  }
};
const hash=s=>createHash('sha256').update(s).digest('hex');
export function capabilityPreflightLegacy(name){return readFileSync(new URL('../../test/fixtures/ax-capability-preflight-'+name+'-handler-before-c05aa.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
export function restoreAXCapabilityPreflightRoute(source,name){
    const p=specs[name],first=source.indexOf(p.start),last=source.indexOf(p.end,first);assert.ok(first>=0&&last>first);
    const legacy=capabilityPreflightLegacy(name);let expected=legacy;
    for(const [before,after] of p.edits){assert.equal(expected.split(before).length-1,1);expected=expected.replace(before,after);}
    assert.equal(source.slice(first,last),expected,'only Task77 captured preflight/provider/foreground stop gates');
    const restored=source.slice(0,first)+legacy+source.slice(last);
    assert.equal(hash(restored),p.hash,'complete preceding C05z '+name+' source; ordinary handlers/authority/codecs unchanged');return restored;
}
