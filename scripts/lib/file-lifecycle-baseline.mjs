import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
const parts=[
  [
    "mode",
    "static NSString *TLinkJSFileNormalizeMode(",
    "BOOL TLinkJSFileModeWrites("
  ],
  [
    "open",
    "+ (instancetype)openPath:",
    "- (void)dealloc"
  ],
  [
    "seek",
    "- (NSDictionary *)seekWhence:",
    "- (NSDictionary *)tell"
  ],
  [
    "flush",
    "- (NSDictionary *)flush",
    "- (NSDictionary *)close"
  ],
  [
    "close",
    "- (NSDictionary *)close\n",
    "\n@end"
  ]
];
export function fileLifecyclePart(source,name){const [,a,b]=parts.find(p=>p[0]===name),start=source.indexOf(a),end=source.indexOf(b,start+a.length);assert.ok(start>=0&&end>start);return source.slice(start,end);}
export function restoreFileLifecycle(source){assert.equal(hash(source),'2b6f23c0701478c9e3aeab498774cae93627c2ccf96f653d5d61be9d0026e0ee','complete C03ag FileHandle');source=source.replace('#include "TLinkJSFileOpen.h"\n','');for(const [name] of parts)source=source.replace(fileLifecyclePart(source,name),readFileSync(new URL('../../test/fixtures/file-lifecycle-'+name+'-before-c03ag.inc',import.meta.url),'utf8').replaceAll('\r\n','\n'));assert.equal(hash(source),'7b263e026e99f64a21f26b6958ef07e0896e91cd9d6220d75d461b1f9ae4774d','complete preceding C03ac FileHandle');return source;}
