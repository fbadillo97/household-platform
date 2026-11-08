import {isDebt,balanceIsOld,localToday} from './accounts.js';
const KINDS=new Set(['checking','savings','credit','mortgage','loan','investment','asset','other']);
export const ASSET_BUCKETS=[['checking','Checking',['checking'],'#28735c'],['savings','Savings',['savings'],'#5b9074'],['investments','Investments',['investment'],'#6b76b8'],['property','Property & Other Assets',['asset','other'],'#b48b42']];
const safeSum=values=>{const total=values.reduce((n,v)=>n+BigInt(v),0n);return total>BigInt(Number.MAX_SAFE_INTEGER)||total<BigInt(Number.MIN_SAFE_INTEGER)?null:Number(total);};
function validBalance(a,today){const s=a.balance_snapshot;if(!s||!KINDS.has(a.kind)||!Number.isSafeInteger(s.amount_minor)||Math.abs(s.amount_minor)>100000000000000||(['asset','other'].includes(a.kind)&&s.amount_minor<0)||s.currency!==a.currency||!/^\d{4}-\d{2}-\d{2}$/.test(s.as_of||''))return false;const d=new Date(s.as_of+'T00:00:00Z');return !Number.isNaN(d.valueOf())&&d.toISOString().slice(0,10)===s.as_of&&s.as_of>='1900-01-01'&&s.as_of<=today;}
export function summarizeWorth(accounts,currency,today=localToday()){
 const inCurrency=accounts.filter(a=>a.currency===currency),eligible=inCurrency.filter(a=>!a.archived_at&&a.include_in_net_worth!==false);
 const known=eligible.filter(a=>validBalance(a,today)),knownIds=new Set(known.map(a=>a.id));
 const missing=eligible.filter(a=>!knownIds.has(a.id)),invalid=missing.filter(a=>a.balance_snapshot),stale=known.filter(a=>balanceIsOld(a.balance_snapshot.as_of,today));
 function metric(rows,net=false){const provided=rows.filter(a=>knownIds.has(a.id));return {ids:rows.map(a=>a.id),count:rows.length,known:provided.length,missing:rows.length-provided.length,minor:provided.length?safeSum(provided.map(a=>net&&isDebt(a)?-a.balance_snapshot.amount_minor:a.balance_snapshot.amount_minor)):rows.length?null:0};}
 const metrics={net:metric(eligible,true),assets:metric(eligible.filter(a=>!isDebt(a))),debts:metric(eligible.filter(isDebt)),cash:metric(eligible.filter(a=>['checking','savings'].includes(a.kind)))};
 if(!eligible.length)metrics.net.minor=null;
 const buckets=ASSET_BUCKETS.map(([id,label,kinds,color])=>{const rows=known.filter(a=>kinds.includes(a.kind)&&a.balance_snapshot.amount_minor>0);return {id,label,color,ids:rows.map(a=>a.id),minor:safeSum(rows.map(a=>a.balance_snapshot.amount_minor))};}).filter(b=>b.ids.length);
 const positiveAssets=safeSum(buckets.map(b=>b.minor??0));const allocationSafe=buckets.every(b=>b.minor!==null)&&positiveAssets!==null;
 const dates=known.map(a=>a.balance_snapshot.as_of).sort();
 return {currency,eligible,known,missing,invalid,stale,metrics,buckets,positiveAssets,allocationSafe,oldest:dates[0]||null,newest:dates.at(-1)||null,
  negativeAssets:safeSum(known.filter(a=>!isDebt(a)&&a.balance_snapshot.amount_minor<0).map(a=>a.balance_snapshot.amount_minor)),
  debtCredits:safeSum(known.filter(a=>isDebt(a)&&a.balance_snapshot.amount_minor<0).map(a=>-a.balance_snapshot.amount_minor)),
  excluded:inCurrency.filter(a=>!a.archived_at&&a.include_in_net_worth===false),archived:inCurrency.filter(a=>a.archived_at),
  assumed:eligible.filter(a=>a.source_metadata?.currency_assumed)};
}
