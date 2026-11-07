import {restoreEventPreparation} from './event-preparation-baseline.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const parts=[
  [
    "permissions",
    "static BOOL TLinkEventEnsureDirectory(void)",
    "static void TLinkEventReleaseFileLock("
  ],
  [
    "reader",
    "static NSMutableDictionary *TLinkEventReadJournal(",
    "static BOOL TLinkEventWriteJournal("
  ],
  [
    "writer",
    "static BOOL TLinkEventWriteJournal(",
    "static NSString *TLinkEventToken("
  ],
  [
    "parser",
    "static NSDictionary *TLinkEventParseBody(",
    "// BEGIN event wait adapter."
  ],
  [
    "wait",
    "// BEGIN event wait adapter.",
    "// END event wait adapter."
  ]
];
export function eventMetadataPart(source,name){const [,a,b]=parts.find(p=>p[0]===name),start=source.indexOf(a),end=source.indexOf(b,start+a.length);assert.ok(start>=0&&end>start);return source.slice(start,end);}
export function restoreEventMetadata(source){source=restoreEventPreparation(source);assert.equal(hash(source),'84c54ae312efeb448cd8a163ba36a0ab816d10c459756cfb51be6ebbf070e5e2','complete C03af event source');source=source.replace('#include "TLinkEventMetadata.h"\n','');for(const [name] of parts)source=source.replace(eventMetadataPart(source,name),readFileSync(new URL('../../test/fixtures/event-metadata-'+name+'-before-c03af.inc',import.meta.url),'utf8').replaceAll('\r\n','\n'));assert.equal(hash(source),'1b939c0e99d852c616e4813ee58e561d2037a954f5b0b0dcc70890593d746a1a','complete preceding C03ae event source');return source;}
