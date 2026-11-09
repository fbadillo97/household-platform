import test from 'node:test';import assert from 'node:assert/strict';import {categoryBreakdown,categoryChanges,savingsRate} from '../src/reports/breakdowns.js';
const row=(id,name,value,series='spending')=>({category_id:id,name,[series+'_minor']:value,entry_count:1});
test('category shares rank net positives and preserve corrections, zero and unassigned amounts',()=>{
 const b=categoryBreakdown([row('a','A',400),row(null,'Unassigned',100),row('c','Credits',-50),row('z','Zero',0)],'spending');
 assert.deepEqual(b.ranked.map(r=>r.value),[400,100,0,-50]);assert.deepEqual(b.ranked.map(r=>r.share),[80,20,null,null]);assert.equal(b.hasAdjustments,true);assert.equal(b.slices.length,2);assert.equal(b.slices[0].share,80);
 const many=categoryBreakdown(Array.from({length:12},(_,i)=>row('a'+i,'Category '+i,i+1)),'spending');assert.equal(many.slices.length,8);assert.equal(many.slices[7].other,true);assert.ok(Math.abs(many.slices.reduce((s,r)=>s+r.fraction,0)-1)<1e-7);assert.equal(categoryBreakdown([row('x','Credit',-1)],'spending').slices.length,0);
});
test('changes retain disappeared and new categories, rank by dollar impact and avoid misleading zero/negative percentages',()=>{
 const changes=categoryChanges([row('a','A',600),row('n','New',700),row('c','Credits',-50)],[row('a','A',400),row('d','Gone',900),row('c','Credits',-100)],'spending');
 assert.deepEqual(changes.map(r=>r.delta),[-900,700,200,50]);assert.equal(changes[0].percent,-100);assert.equal(changes[1].percent,null);assert.equal(changes[1].baseline,'No prior amount');assert.equal(changes[2].percent,50);assert.equal(changes[3].percent,null);
 assert.deepEqual(categoryChanges([],[],'income'),[]);assert.throws(()=>categoryChanges([row('a','A',Number.MAX_SAFE_INTEGER)],[row('a','A',-Number.MAX_SAFE_INTEGER)],'spending'),/supported/);
});
test('cash-flow savings rate is signed, unclamped and unavailable without positive income',()=>{
 assert.equal(savingsRate(250000,190000),76);assert.equal(savingsRate(100,-25),-25);assert.equal(savingsRate(100,150),150);assert.equal(savingsRate(0,-100),null);assert.equal(savingsRate(-1,100),null);assert.throws(()=>savingsRate(1.5,1));
});
