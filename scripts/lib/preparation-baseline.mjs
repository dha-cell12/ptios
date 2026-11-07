import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const spec={
  "event": {
    "hash": "1b939c0e99d852c616e4813ee58e561d2037a954f5b0b0dcc70890593d746a1a",
    "before": "38c3ebb5d8eb26cd49c7d0b172a9c0811428dcb8f8f7b6eb52c1a728761bd9a4",
    "parts": [
      {
        "name": "integer",
        "start": "static BOOL TLinkEventJournalInteger(",
        "end": "static NSMutableDictionary *TLinkEventReadJournal("
      },
      {
        "name": "token",
        "start": "static NSString *TLinkEventToken(",
        "end": "static NSDictionary *TLinkEventBoundedPayload("
      },
      {
        "name": "publish",
        "start": "NSDictionary *TLinkEventChannelPublish(",
        "end": "static BOOL TLinkEventTopicMatches("
      },
      {
        "name": "batch",
        "start": "static NSDictionary *TLinkEventBatchFromJournal(",
        "end": "static NSDictionary *TLinkEventParseBody("
      },
      {
        "name": "status",
        "start": "NSDictionary *TLinkEventChannelStatus(void)",
        "end": null
      }
    ]
  },
  "history": {
    "hash": "0eee5bbd9b490cf0467b646276270cd4241503973156b703ee7c6c093df12a77",
    "before": "fb1f737e14190c13ed88acd8bab3cd83c24e3b3df5ee5285ef84512b4b789482",
    "parts": [
      {
        "name": "sanitize",
        "start": "static NSString *TLinkRunHistorySanitize(",
        "end": "// Validate direct directories"
      }
    ]
  }
};
export function preparationBefore(kind,name){return readFileSync(new URL('../../test/fixtures/preparation-'+kind+'-'+name+'-before-c03ad.inc',import.meta.url),'utf8').replaceAll('\r\n','\n');}
export function preparationPart(source,kind,name){const p=spec[kind].parts.find(p=>p.name===name),a=source.indexOf(p.start),b=p.end?source.indexOf(p.end,a):source.length;assert.ok(a>=0&&b>a);return source.slice(a,b);}
export function restorePreparation(source,kind){assert.equal(hash(source),spec[kind].hash,'complete current preparation source');source=source.replace('#include "TLinkASCIIPreparation.h"\n','');for(const part of spec[kind].parts)source=source.replace(preparationPart(source,kind,part.name),preparationBefore(kind,part.name));assert.equal(hash(source),spec[kind].before,'complete preceding preparation source');return source;}
export function checkPreparationCore(source){assert.equal(hash(source),'4526a0918485e316181205d52ade7a5911a9bffbf985a6ca728dbc444b737581','complete ASCII preparation core');}
