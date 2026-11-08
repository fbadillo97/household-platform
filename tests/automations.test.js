import test from 'node:test';
import assert from 'node:assert/strict';
import {automationStatement,automationChange} from '../src/automations.js';
import {pageFromHash} from '../src/navigation.js';
import {ledgerPayload,EMPTY_COLUMN_FILTERS} from '../src/finance.js';
const refs={payees:[{id:'p',name:'Mock insurer'}],accounts:[{id:'a',name:'Mock bank'}],categories:[{id:'c',name:'Insurance'}]};
test('automation statements describe the saved predicates and actions including signed exact amounts',()=>{
 const text=automationStatement({conditions:{payee_id:'p',account_id:'a',amount_min_minor:-12500,amount_max_minor:-12500,currency:'CAD'},actions:{add_tags:['Insurance'],category_id:'c',needs_attention:true}},refs);
 assert.match(text,/payee is Mock insurer/);assert.match(text,/account is Mock bank/);assert.match(text,/signed amount is -\$125\.00 CAD/);assert.match(text,/add tag “Insurance”/);assert.match(text,/category to Insurance/);assert.match(text,/flag for attention/);
 const range=automationStatement({conditions:{description_contains:'Mock',amount_min_minor:0,amount_max_minor:10000,currency:'USD'},actions:{payee_id:null,review_status:'unreviewed',needs_attention:false}},refs);
 assert.match(range,/at least.*0\.00 USD/);assert.match(range,/at most.*100\.00 USD/);assert.match(range,/Unassigned/);assert.match(range,/mark unreviewed/);assert.match(range,/clear the attention flag/);
});
test('recognition and historical change labels remain understandable without printing raw configuration',()=>{
 assert.equal(automationStatement({kind:'alias',description:'MOCK #1',payee_id:'p'},refs),'Recognize “MOCK #1” as Mock insurer.');
 assert.equal(automationChange({tags_override:null,payee_id:'p'},refs),'Payee: Mock insurer · Tags: Imported tags');
 assert.match(automationChange({category_id:null,needs_attention:false},refs),/Category: Unassigned/);
});
test('automation settings deep links and affected record scopes remain explicit',()=>{
 assert.equal(pageFromHash('#settings/automations'),'settings');assert.equal(pageFromHash('#settings/unknown'),'dashboard');
 const payload=ledgerPayload({view:{columns:{...EMPTY_COLUMN_FILTERS,automationSource:'rule:mock',automationEvent:'mock-event'},sort:'date',direction:'desc',offset:0}});
 assert.equal(payload.automation_source,'rule:mock');assert.equal(payload.automation_event,'mock-event');
});
