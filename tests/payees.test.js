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
import {payeeDirectory} from '../src/payees.js';
test('payee groups filter independently of kind, search aliases/tags and sort exact activity with stable ties',()=>{
 const rows=[{id:'a',name:'Mock bank',kind:'institution',aliases:['MOCK BANK 01'],tags:[{id:'t',name:'Mock family'}],transaction_count:2,last_transaction:'2026-10-01'},{id:'b',name:'Mock market',kind:'business',aliases:[],tags:[],transaction_count:5,last_transaction:'2026-10-02'},{id:'c',name:'Old',kind:'business',aliases:[],archived_at:'2026-01-01'}];
 assert.deepEqual(payeeDirectory(rows,{tag:'t'}).map(p=>p.id),['a']);assert.deepEqual(payeeDirectory(rows,{tag:'__untagged'}).map(p=>p.id),['b']);assert.deepEqual(payeeDirectory(rows,{query:'family'}).map(p=>p.id),['a']);assert.deepEqual(payeeDirectory(rows,{query:'BANK 01'}).map(p=>p.id),['a']);assert.deepEqual(payeeDirectory(rows,{sort:'count',direction:'desc'}).map(p=>p.id),['b','a']);assert.deepEqual(payeeDirectory(rows,{sort:'last',direction:'asc'}).map(p=>p.id),['a','b']);assert.equal(rows[0].id,'a');
});
