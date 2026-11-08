import test from 'node:test';import assert from 'node:assert/strict';
import {parseCSV,defaultSelection,commitSelection} from '../src/import.js';
import {SessionFence} from '../src/lifecycle.js';
test('CSV supports quoted commas, UTF8 BOM, and rejects malformed headers/quotes',()=>{
 assert.equal(parseCSV('\ufeffdate,description,amount\n2026-01-01,"Mock, shop",-1.25')[0].description,'Mock, shop');
 assert.throws(()=>parseCSV('Date,description,amount\n2026-01-01,A,1'));
 assert.throws(()=>parseCSV('date,description,amount\n2026-01-01,"unclosed,1'));
 assert.equal(parseCSV('date,description,amount\n2026-01-01,A,1,extra')[0].parse_error,'Invalid column count');
});
test('default selection excludes errors and duplicate overrides are explicit',()=>{
 const batch={id:'batch',rows:[{id:'a',error:null,duplicate:false},{id:'b',error:null,duplicate:true},{id:'c',error:'Invalid',duplicate:false}]};
 assert.deepEqual(defaultSelection(batch),['a']);assert.deepEqual(commitSelection(batch,['a','b']),{id:'batch',row_ids:['a','b'],duplicate_ids:['b']});
});
test('sign-out or revocation prevents delayed private results from restoring state',async()=>{
 const fence=new SessionFence();let resolve;const delayed=fence.run(()=>new Promise(r=>resolve=r));fence.invalidate();resolve({private:'mock'});await assert.rejects(delayed,/Stale session/);
 assert.equal(await fence.run(async()=>42),42);
});

import {phaseForAccess} from '../src/access.js';
test('approved email sessions cannot render protected finance and loose claims cannot enable access',()=>{
 assert.equal(phaseForAccess({status:'approved',passkey_verified:false}),'passkey_required');
 assert.equal(phaseForAccess({status:'approved',passkey_verified:'true'}),'passkey_required');
 assert.equal(phaseForAccess({status:'approved',user_metadata:{passkey:true}}),'passkey_required');
 assert.equal(phaseForAccess({status:'approved',passkey_verified:true}),'approved');
 for(const status of ['pending','removed','rejected'])assert.equal(phaseForAccess({status,passkey_verified:true}),status);
});
