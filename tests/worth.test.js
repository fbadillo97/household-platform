import test from 'node:test';
import assert from 'node:assert/strict';
import {summarizeWorth} from '../src/worth.js';
const today='2026-11-08';
const account=(id,kind,minor,currency='CAD',extra={})=>({id,kind,currency,include_in_net_worth:true,balance_snapshot:minor===null?null:{amount_minor:minor,currency,as_of:today},...extra});
test('net worth excludes archived/excluded/other-currency accounts and retains signed credits and overdrafts',()=>{
 const rows=[account('checking','checking',200000),account('savings','savings',100000),account('invest','investment',400000),account('home','asset',10000000),account('card','credit',150000),account('loan','loan',2500000),account('overdraft','checking',-10000),account('credit','credit',-5000),account('foreign','checking',900000,'USD'),account('exclude','asset',5000000,'CAD',{include_in_net_worth:false}),account('closed','loan',3000000,'CAD',{archived_at:today})];
 const s=summarizeWorth(rows,'CAD',today);
 assert.equal(s.metrics.assets.minor,10690000);assert.equal(s.metrics.debts.minor,2645000);assert.equal(s.metrics.net.minor,8045000);assert.equal(s.metrics.cash.minor,290000);
 assert.equal(s.positiveAssets,10700000);assert.equal(s.negativeAssets,-10000);assert.equal(s.debtCredits,5000);assert.equal(s.excluded.length,1);assert.equal(s.archived.length,1);
 assert.deepEqual(s.metrics.cash.ids,['checking','savings','overdraft']);assert.equal(summarizeWorth(rows,'USD',today).metrics.net.minor,900000);
});
test('missing balances are not zero, invalid snapshots are omitted and stale dates remain visible',()=>{
 const rows=[account('zero','checking',0),account('missing','savings',null),account('stale','investment',100,'CAD',{balance_snapshot:{amount_minor:100,currency:'CAD',as_of:'2026-09-01'}}),account('invalid','credit',10,'CAD',{balance_snapshot:{amount_minor:10,currency:'USD',as_of:today}}),account('future','asset',100,'CAD',{balance_snapshot:{amount_minor:100,currency:'CAD',as_of:'2026-11-09'}})];
 const s=summarizeWorth(rows,'CAD',today);assert.equal(s.known.length,2);assert.equal(s.missing.length,3);assert.equal(s.invalid.length,2);assert.equal(s.stale.length,1);assert.equal(s.oldest,'2026-09-01');assert.equal(s.newest,today);assert.equal(s.metrics.net.minor,100);assert.equal(s.metrics.cash.minor,0);assert.equal(s.metrics.cash.missing,1);assert.equal(s.metrics.debts.minor,null);
 const missing=summarizeWorth([account('empty','checking',null)],'CAD',today);assert.equal(missing.metrics.net.minor,null);assert.equal(missing.metrics.assets.minor,null);assert.equal(missing.buckets.length,0);
 const zero=summarizeWorth([account('zero','checking',0)],'CAD',today);assert.equal(zero.metrics.net.minor,0);assert.equal(zero.buckets.length,0);
 const empty=summarizeWorth([],'CAD',today);assert.equal(empty.metrics.net.minor,null);
});
test('unsafe aggregate amounts are unavailable instead of rounded and negative net worth remains signed',()=>{
 const s=summarizeWorth(Array.from({length:100},(_,i)=>account('large-'+i,'asset',100000000000000)),'CAD',today);assert.equal(s.metrics.net.minor,null);assert.equal(s.metrics.assets.minor,null);assert.equal(s.allocationSafe,false);
 const debt=summarizeWorth([account('bank','checking',100),account('debt','mortgage',500)],'CAD',today);assert.equal(debt.metrics.net.minor,-400);
});
test('equity subtracts linked debt once, keeps unsecured debt separate and preserves net worth',()=>{
 const rows=[account('home','asset',10000000),account('mortgage','mortgage',6000000,'CAD',{secured_asset_id:'home'}),account('car','asset',1000000),account('car-loan','loan',1200000,'CAD',{secured_asset_id:'car'}),account('bank','checking',200000),account('card','credit',50000)];
 const s=summarizeWorth(rows,'CAD',today);
 assert.equal(s.metrics.assets.minor,11200000);assert.equal(s.metrics.debts.minor,7250000);assert.equal(s.metrics.net.minor,3950000);
 assert.equal(s.positiveEquity,4200000);assert.equal(s.negativeEquity,-200000);assert.equal(s.unlinkedDebtMinor,50000);
 assert.equal(s.buckets.find(b=>b.id==='property').minor,4000000);assert.deepEqual(s.buckets.find(b=>b.id==='property').ids,['home','mortgage']);
 assert.equal(s.positiveEquity+s.negativeEquity-s.unlinkedDebtMinor,s.metrics.net.minor);
 rows.push(account('credit-adjustment','loan',-10000,'CAD',{secured_asset_id:'home'}));
 const credit=summarizeWorth(rows,'CAD',today);assert.equal(credit.buckets.find(b=>b.id==='property').minor,4010000);
});
test('unknown secured balances never become gross-value equity; included cohorts and zero/negative equity stay honest',()=>{
 const rows=[account('home','asset',10000000),account('mortgage','mortgage',null,'CAD',{secured_asset_id:'home'})];
 const missing=summarizeWorth(rows,'CAD',today);assert.equal(missing.positiveEquity,0);assert.equal(missing.buckets.length,0);assert.equal(missing.missingEquity.length,1);
 rows[1].include_in_net_worth=false;assert.equal(summarizeWorth(rows,'CAD',today).positiveEquity,10000000);
 rows[1]=account('mortgage','mortgage',10000000,'CAD',{secured_asset_id:'home'});assert.equal(summarizeWorth(rows,'CAD',today).positiveEquity,0);
 rows[1]=account('mortgage','mortgage',11000000,'CAD',{secured_asset_id:'home'});assert.equal(summarizeWorth(rows,'CAD',today).negativeEquity,-1000000);
 rows[0].include_in_net_worth=false;const excluded=summarizeWorth(rows,'CAD',today);assert.equal(excluded.unlinkedDebtMinor,11000000);
 const unknown=summarizeWorth([account('unknown','loan',null)],'CAD',today);assert.equal(unknown.unlinkedDebtMinor,null);
});
