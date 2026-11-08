import test from 'node:test';
import assert from 'node:assert/strict';
import {payeeKey,payeeAliases} from '../src/payees.js';
import {bulkValue,bulkDescription,bulkPreview} from '../src/bulk.js';
import {ledgerPayload,EMPTY_COLUMN_FILTERS} from '../src/finance.js';
test('payee alias recognition is exact and conservative; duplicate/oversize input is rejected',()=>{
 assert.equal(payeeKey('  MOCK   STORE #12 '),'mock store #12');
 assert.notEqual(payeeKey('Mock store #12'),payeeKey('Mock store #13'));
 assert.deepEqual(payeeAliases('Mock store #12\n\nMock Store #13'),['Mock store #12','Mock Store #13']);
 assert.throws(()=>payeeAliases('Mock\n  MOCK '),/Repeated/);
 assert.throws(()=>payeeAliases('a'.repeat(501)),/500/);
 assert.throws(()=>payeeAliases(Array.from({length:51},(_,i)=>String(i)).join('\n')),/50/);
});
test('payee filters and bulk previews preserve explicit clearing and show the canonical name',()=>{
 const payees=[{id:'p',name:'Mock market'}];
 assert.equal(bulkValue('payee','__unassigned'),null);
 assert.throws(()=>bulkValue('payee',''),/Choose a payee/);
 assert.equal(bulkDescription('payee','p',[],payees),'Set payee to Mock market');
 assert.equal(bulkPreview({payee_id:null},'payee','p',[],payees),'Unassigned → Mock market');
 assert.equal(ledgerPayload({view:{columns:{...EMPTY_COLUMN_FILTERS,payee:'p'},sort:'payee',direction:'asc',offset:0}}).payee_id,'p');
});
