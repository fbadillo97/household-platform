import test from 'node:test';
import assert from 'node:assert/strict';
import {buildHistory,inspectHistory,historyDetails,sampleHistory,historyRange,shiftDate,dayNumber} from '../src/history.js';
import {formatMoney} from '../src/money.js';
const a=(id,kind='checking',extra={})=>({id,name:'Mock '+id,kind,currency:'CAD',include_in_net_worth:true,...extra});
const e=(id,as_of,amount_minor,extra={})=>({id:id+as_of,account_id:id,as_of,amount_minor,currency:'CAD',correction_count:0,...extra});
const data=(accounts,entries,extra={})=>({scope:'net_worth',currency:'CAD',from:'2026-01-01',to:'2026-02-01',accounts,entries,...extra});
test('history carries balances forward but never backward, preserves zeros and breaks coverage when an account first appears',()=>{
 const raw=data([a('bank'),a('card','credit')],[e('bank','2026-01-05',10000),e('card','2026-01-15',3000)]),before=structuredClone(raw),m=buildHistory(raw);
 assert.equal(m.points[0].minor,null);assert.equal(inspectHistory(m,'2026-01-04').known,0);assert.equal(inspectHistory(m,'2026-01-10').minor,10000);assert.equal(inspectHistory(m,'2026-01-10').partial,true);
 assert.equal(m.last.minor,7000);assert.equal(m.last.partial,false);assert.notEqual(m.points.find(p=>p.date==='2026-01-05').coverage_version,m.points.find(p=>p.date==='2026-01-15').coverage_version);assert.equal(m.change,null);
 const details=historyDetails(m,'2026-01-10');assert.equal(details.find(d=>d.account.id==='bank').entry.as_of,'2026-01-05');assert.equal(details.find(d=>d.account.id==='card').entry,null);assert.deepEqual(raw,before);
 const zero=buildHistory(data([a('bank')],[e('bank','2025-12-01',0,{carry_in:true})]));assert.equal(zero.first.minor,0);assert.equal(zero.last.minor,0);assert.equal(zero.change,0);assert.equal(zero.percent,null);assert.equal(zero.observations,0);assert.equal(zero.last.stale,1);
});
test('net worth uses current included cohort and signed debts, while an individual archived account retains its amount-owed history',()=>{
 const accounts=[a('bank'),a('card','credit'),a('excluded','asset',{include_in_net_worth:false}),a('archived','loan',{archived_at:'2026-01-20'}),a('foreign','checking',{currency:'USD'})];
 const entries=[e('bank','2025-12-20',1000),e('card','2025-12-20',-200),e('excluded','2026-01-01',10000),e('archived','2026-01-01',5000),e('foreign','2026-01-01',10000,{currency:'USD'}),e('bank','2026-01-10',1500,{correction_count:2})];
 const m=buildHistory(data(accounts,entries));assert.equal(m.accounts.length,2);assert.equal(m.first.minor,1200);assert.equal(m.last.minor,1700);assert.equal(m.change,500);assert.equal(m.corrections,2);assert.equal(m.last.carried,2);
 const individual=buildHistory(data([accounts[3]],[e('archived','2026-01-01',5000),e('archived','2026-01-15',4000)],{scope:'account'}));assert.equal(individual.first.minor,5000);assert.equal(individual.last.minor,4000);assert.equal(individual.change,-1000);
 const negativeStart=buildHistory(data([a('card','credit')],[e('card','2026-01-01',5000),e('card','2026-01-20',4000)]));assert.equal(negativeStart.change,1000);assert.equal(negativeStart.percent,null);
 const bad=buildHistory(data([a('bank')],[e('bank','2026-01-01',100),e('bank','2026-01-20',200,{currency:'USD'})]));assert.equal(bad.last.minor,null);assert.equal(bad.last.invalid,1);assert.equal(bad.last.known,0);
});
test('range dates handle leap years and unknown/invalid histories fail clearly',()=>{
 assert.equal(shiftDate('2024-02-28',1),'2024-02-29');assert.equal(shiftDate('2024-02-29',1),'2024-03-01');assert.deepEqual(historyRange('30d','2026-01-10'),{from:'2025-12-12',to:'2026-01-10'});assert.equal(historyRange('all','2026-01-10').from,null);
 assert.throws(()=>dayNumber('2026-02-29'));assert.throws(()=>buildHistory(data([a('bank')],[e('bank','2026-01-01',1),e('bank','2026-01-01',2)])),/Repeated date/);
 assert.throws(()=>buildHistory(data([a('bank')],[],{from:'2026-02-02'})),/Start date/);assert.throws(()=>buildHistory(data([a('bank'),a('card')],[],{scope:'account'})),/invalid/);
 const empty=buildHistory(data([a('bank')],[]));assert.equal(empty.points.every(p=>p.minor===null),true);assert.throws(()=>inspectHistory(empty,'2025-01-01'),/within/);
 const tooLarge=buildHistory(data(Array.from({length:100},(_,i)=>a('a'+i)),Array.from({length:100},(_,i)=>e('a'+i,'2026-01-01',100000000000000))));assert.equal(tooLarge.last.minor,null);
});
test('chart simplification retains extremes and both sides of coverage changes',()=>{
 const points=Array.from({length:1000},(_,i)=>({date:'mock-'+i,minor:i===333?-99999:i===700?99999:i,coverage_version:i<500?1:2,partial:i<500}));
 const sampled=sampleHistory(points);assert.ok(sampled.length<points.length);for(const index of [0,333,499,500,700,999])assert.ok(sampled.includes(points[index]),'lost point '+index);
});
test('money formatting keeps exact pennies at the safe-integer boundary',()=>{
 assert.equal(formatMoney(9007199254740991),'$90,071,992,547,409.91');assert.equal(formatMoney(-1),'-$0.01');assert.equal(formatMoney(0),'$0.00');assert.equal(formatMoney(-9007199254740991),'-$90,071,992,547,409.91');assert.throws(()=>formatMoney(1.2));
});
