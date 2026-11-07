import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const parts=[
  [
    "writer",
    "static BOOL TLinkRunHistoryWriteJSON(",
    "static BOOL TLinkRunHistoryWriteIndex("
  ],
  [
    "redact",
    "static NSString *TLinkRunHistoryRedactText(",
    "static NSArray<NSString *> *TLinkRunHistoryBoundedLogTail("
  ],
  [
    "tail",
    "static NSArray<NSString *> *TLinkRunHistoryBoundedLogTail(",
    "static BOOL TLinkRunHistoryRemoveArtifact("
  ],
  [
    "prune",
    "static void TLinkRunHistoryPrune(",
    "NSDictionary *TLinkRunHistoryBegin("
  ],
  [
    "begin",
    "NSDictionary *TLinkRunHistoryBegin(",
    "NSDictionary *TLinkRunHistoryFinish("
  ],
  [
    "finish",
    "NSDictionary *TLinkRunHistoryFinish(",
    "// Failed status counts/runs"
  ],
  [
    "snapshot",
    "NSDictionary *TLinkRunHistorySnapshot(",
    null
  ]
];
export function historyWorkPart(source,name){const [,a,b]=parts.find(p=>p[0]===name),start=source.indexOf(a),end=b?source.indexOf(b,start+a.length):source.length;assert.ok(start>=0&&end>start);return source.slice(start,end);}
export function restoreHistoryWork(source){assert.equal(hash(source),'56914732f5164cd728098a60c6d143b1ca4c9aa87261ccda69ec3080cd83fabb','complete C03ae source');source=source.replace('#include "TLinkTextTail.h"\n','');for(const [name] of parts)source=source.replace(historyWorkPart(source,name),readFileSync(new URL('../../test/fixtures/history-work-'+name+'-before-c03ae.inc',import.meta.url),'utf8').replaceAll('\r\n','\n'));assert.equal(hash(source),'0eee5bbd9b490cf0467b646276270cd4241503973156b703ee7c6c093df12a77','complete preceding C03ad history source');return source;}
