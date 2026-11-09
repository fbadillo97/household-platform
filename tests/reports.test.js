import test from 'node:test';import assert from 'node:assert/strict';import {reportRange,reportPayload,rangeDays,changeLabel} from '../src/reports/model.js';import {operationEndpoint} from '../src/planning.js';
test('report presets and comparison windows use exact equal day lengths across leap years and month ends',()=>{
 assert.deepEqual(reportRange('month','2026-11-08'),{from:'2026-11-01',to:'2026-11-08'});assert.deepEqual(reportRange('last_month','2024-03-31'),{from:'2024-02-01',to:'2024-02-29'});assert.deepEqual(reportRange('six_months','2026-02-08'),{from:'2025-09-01',to:'2026-02-08'});
 const p=reportPayload({from:'2024-03-01',to:'2024-03-31',currency:'CAD'},'2024-03-31');assert.equal(rangeDays(p.compare_from,p.compare_to),31);assert.equal(p.compare_to,'2024-02-29');assert.equal(p.compare_from,'2024-01-30');assert.equal('compare_from' in reportPayload({from:'2024-03-01',to:'2024-03-31',currency:'USD',compare:false},'2024-03-31'),false);
});
test('invalid dates, future dates, reversed or excessive ranges and duplicate accounts reject before requesting reports',()=>{
 for(const [from,to] of [['2026-02-30','2026-03-01'],['2026-11-09','2026-11-10'],['2026-11-08','2026-11-01'],['2020-01-01','2026-11-08']])assert.throws(()=>reportPayload({from,to,currency:'CAD'},'2026-11-08'));
 assert.throws(()=>reportPayload({from:'2026-01-01',to:'2026-01-31',currency:'CAD',accountIds:['a','a']},'2026-11-08'));
 assert.equal(changeLabel(100,-50),150);assert.throws(()=>changeLabel(Number.MAX_SAFE_INTEGER,-1));assert.equal(operationEndpoint('reports_overview'),'household_reports_v1');assert.throws(()=>operationEndpoint('reports_arbitrary_sql'));
});
