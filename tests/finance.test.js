import test from 'node:test';
import assert from 'node:assert/strict';
import {summarizeRows,filterRows,tagNames} from '../src/finance.js';
const rows=[{id:'1',account_id:'a',date:'2026-10-01',description:'Mock shop',category_id:'food',amount_minor:-125,source_data:{tags:[{id:'tag',name:'Renovation'}]}},{id:'2',account_id:'a',date:'2026-10-02',description:'Mock pay',category_id:'salary',amount_minor:2000},{id:'3',account_id:'b',date:'2026-09-01',description:'Mock transfer',category_id:'transfer',amount_minor:-300}];
test('unclassified activity uses exact cents',()=>{
 assert.deepEqual(summarizeRows(rows),{count:3,inflow:2000,outflow:425,net:1575});
 assert.throws(()=>summarizeRows([{amount_minor:1.2}]),/Invalid stored amount/);
});
test('account/month/category/tag filters keep unrelated rows out of the view',()=>{
 const categories=[{id:'food',name:'Groceries'}];
 assert.equal(filterRows(rows,{accountId:'a',month:'2026-10'},categories).length,2);
 assert.deepEqual(filterRows(rows,{query:'renovation'},categories).map(t=>t.id),['1']);
 assert.deepEqual(filterRows(rows,{query:'groceries'},categories).map(t=>t.id),['1']);
 assert.deepEqual(tagNames(rows[1]),[]);
});

import {pageFromHash} from '../src/navigation.js';
test('page links resolve safely on static hosting',()=>{
 assert.equal(pageFromHash(''),'dashboard');
 assert.equal(pageFromHash('#dashboard'),'dashboard');
 assert.equal(pageFromHash('#transactions'),'transactions');assert.equal(pageFromHash('#accounts'),'accounts');
 assert.equal(pageFromHash('#/settings'),'settings');
 assert.equal(pageFromHash('#unknown'),'dashboard');
 assert.equal(pageFromHash('#__proto__'),'dashboard');
});

import {ledgerPayload,amountFilterMinor,EMPTY_COLUMN_FILTERS} from '../src/finance.js';
test('amount filters use signed integer cents and reject ambiguous ranges',()=>{
 assert.equal(amountFilterMinor('-12.35'),-1235);assert.equal(amountFilterMinor('+0.10'),10);assert.equal(amountFilterMinor(''),null);
 assert.throws(()=>amountFilterMinor('1.001'));assert.throws(()=>amountFilterMinor('1,000'));
 const view={columns:{...EMPTY_COLUMN_FILTERS,minAmount:'-2.00',maxAmount:'0.00'},sort:'amount',direction:'asc',offset:50};
 const payload=ledgerPayload({accountId:'mock',month:'2026-10',query:'shop',view});
 assert.equal(payload.min_minor,-200);assert.equal(payload.max_minor,0);assert.equal(payload.offset,50);assert.equal(payload.sort,'amount');
 assert.throws(()=>ledgerPayload({view:{...view,columns:{...EMPTY_COLUMN_FILTERS,minAmount:'10',maxAmount:'-10'}}}));
});


test('confirmed transfers and card payments are excluded on both sides and across account/month filters',()=>{
 const data=[
  {id:'salary',account_id:'bank',date:'2026-10-01',amount_minor:2000},
  {id:'purchase',account_id:'card',date:'2026-10-02',amount_minor:-300},
  {id:'payment-out',account_id:'bank',date:'2026-10-31',amount_minor:-1000,flow_type:'credit_card_payment',transfer_peer_id:'payment-in'},
  {id:'payment-in',account_id:'card',date:'2026-11-01',amount_minor:1000,flow_type:'credit_card_payment',transfer_peer_id:'payment-out'},
  {id:'unlinked',account_id:'bank',date:'2026-10-01',amount_minor:-500,flow_type:'transfer'}
 ];
 assert.deepEqual(summarizeRows(data),{count:5,inflow:2000,outflow:300,net:1700});
 assert.deepEqual(summarizeRows(filterRows(data,{month:'2026-10'},[])),{count:4,inflow:2000,outflow:300,net:1700});
 assert.deepEqual(summarizeRows(filterRows(data,{accountId:'card'},[])),{count:2,inflow:0,outflow:300,net:-300});
 assert.equal(ledgerPayload({view:{columns:{...EMPTY_COLUMN_FILTERS},flow:'unlinked_transfer',sort:'date',direction:'desc',offset:0}}).flow,'unlinked_transfer');
});

import {pageHash,isAdministration} from '../src/navigation.js';
test('Administration routes preserve legacy links and identify the expandable group',()=>{assert.equal(pageFromHash('#administration/settings'),'settings');assert.equal(pageFromHash('#administration/transfers'),'transfer_logs');assert.equal(pageFromHash('#settings/automations'),'settings');assert.equal(pageHash('settings/automations'),'#administration/settings/automations');assert.equal(isAdministration('settings'),true);assert.equal(isAdministration('dashboard'),false);});
