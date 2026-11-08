import {isDebt,localToday} from './accounts.js';
const DAY=86400000;
const KINDS=new Set(['checking','savings','credit','mortgage','loan','investment','asset','other']);
export function dayNumber(value){if(!/^\d{4}-\d{2}-\d{2}$/.test(value||''))throw Error('Use a valid date.');const ms=Date.parse(value+'T00:00:00Z');if(!Number.isFinite(ms)||new Date(ms).toISOString().slice(0,10)!==value||value<'1900-01-01')throw Error('Use a valid date.');return ms/DAY;}
export const shiftDate=(value,days)=>new Date((dayNumber(value)+days)*DAY).toISOString().slice(0,10);
export function historyRange(preset,today=localToday()){
 if(preset==='all')return {from:null,to:today};
 const days={'30d':30,'90d':90,'1y':365}[preset];if(!days)throw Error('Choose a history range.');return {from:shiftDate(today,1-days),to:today};
}
const checked=value=>value>BigInt(Number.MAX_SAFE_INTEGER)||value<BigInt(Number.MIN_SAFE_INTEGER)?null:Number(value);
export function validHistoryEntry(e,a){return KINDS.has(a.kind)&&e.currency===a.currency&&Number.isSafeInteger(e.amount_minor)&&Math.abs(e.amount_minor)<=100000000000000&&(!['asset','other'].includes(a.kind)||e.amount_minor>=0);}
export function buildHistory(data){
 if(!data||!['account','net_worth'].includes(data.scope)||!Array.isArray(data.accounts)||!Array.isArray(data.entries)||data.accounts.length>500||data.entries.length>10000)throw Error('The history response is invalid. Refresh and try again.');
 const fromDay=dayNumber(data.from),toDay=dayNumber(data.to);if(fromDay>toDay)throw Error('Start date must not follow end date.');
 const accounts=data.accounts.filter(a=>a.currency===data.currency&&(data.scope==='account'||(!a.archived_at&&a.include_in_net_worth!==false)));
 if(data.scope==='account'&&accounts.length!==1)throw Error('The account history response is invalid.');
 const byId=new Map(accounts.map(a=>[a.id,a]));if(byId.size!==accounts.length)throw Error('Repeated account in history.');
 const entries=data.entries.filter(e=>byId.has(e.account_id)).map(e=>({...e,day:dayNumber(e.as_of)})).filter(e=>e.day<=toDay).sort((a,b)=>a.day-b.day||a.account_id.localeCompare(b.account_id));
 const seen=new Set();for(const e of entries){const key=e.account_id+':'+e.as_of;if(seen.has(key))throw Error('Repeated date in history. Refresh and try again.');seen.add(key);}
 const dates=[...new Set([data.from,data.to,...entries.filter(e=>e.day>=fromDay).map(e=>e.as_of)])].sort();
 const current=new Map();let cursor=0,assets=0n,debts=0n,cash=0n,coverageVersion=0;
 function adjust(e,direction){if(!e?.valid)return;const a=byId.get(e.account_id),amount=BigInt(e.amount_minor)*BigInt(direction);if(isDebt(a))debts+=amount;else assets+=amount;if(['checking','savings'].includes(a.kind))cash+=amount;}
 const points=[];
 for(const date of dates){const day=dayNumber(date);while(cursor<entries.length&&entries[cursor].day<=day){const raw=entries[cursor++],previous=current.get(raw.account_id);adjust(previous,-1);const next={...raw,valid:validHistoryEntry(raw,byId.get(raw.account_id))};if(!!previous?.valid!==next.valid)coverageVersion++;current.set(raw.account_id,next);adjust(next,1);}
  let known=0,observed=0,stale=0,invalid=0,oldest=null;for(const e of current.values()){if(!e.valid){invalid++;continue;}known++;if(e.day===day)observed++;if(day-e.day>30)stale++;if(oldest===null||e.as_of<oldest)oldest=e.as_of;}
  const value=data.scope==='account'?assets+debts:assets-debts;
  points.push({date,day,minor:known?checked(value):null,assets_minor:known?checked(assets):null,debts_minor:known?checked(debts):null,cash_minor:known?checked(cash):null,known,total:accounts.length,missing:accounts.length-known,partial:known<accounts.length,stale,invalid,observed,carried:known-observed,oldest,coverage_version:coverageVersion});
 }
 const first=points[0],last=points.at(-1);let change=null,percent=null;
 if(first&&last&&!first.partial&&!last.partial&&first.minor!==null&&last.minor!==null){change=checked(BigInt(last.minor)-BigInt(first.minor));if(change!==null&&first.minor>0)percent=change/Math.abs(first.minor)*100;}
 const plotted=sampleHistory(points);
 return {scope:data.scope,currency:data.currency,accounts,entries,points,plotted,sampled:plotted.length<points.length,first,last,change,percent,savedDates:new Set(entries.map(e=>e.as_of)).size,observations:entries.filter(e=>e.day>=fromDay).length,corrections:entries.reduce((n,e)=>n+Number(e.correction_count||0),0)};
}
export function sampleHistory(points){
 if(points.length<=240)return points;
 const keep=new Set([0,points.length-1]);const width=Math.ceil(points.length/60);
 for(let start=0;start<points.length;start+=width){const end=Math.min(points.length-1,start+width-1);keep.add(start);keep.add(end);let min=start,max=start;for(let i=start;i<=end;i++){if(points[i].minor!==null&&(points[min].minor===null||points[i].minor<points[min].minor))min=i;if(points[i].minor!==null&&(points[max].minor===null||points[i].minor>points[max].minor))max=i;}keep.add(min);keep.add(max);}
 for(let i=1;i<points.length;i++)if(points[i].coverage_version!==points[i-1].coverage_version||points[i].partial!==points[i-1].partial||(points[i].minor===null)!==(points[i-1].minor===null)){keep.add(i-1);keep.add(i);}
 return [...keep].sort((a,b)=>a-b).map(i=>points[i]);
}
export function historyDetails(model,date){const day=dayNumber(date),latest=new Map();for(const e of model.entries){if(e.day>day)break;latest.set(e.account_id,e);}return model.accounts.map(a=>{const e=latest.get(a.id);return {account:a,entry:e||null,valid:e?validHistoryEntry(e,a):false,carried:e?e.day<day:false,stale:e?day-e.day>30:false};});}

export function inspectHistory(model,date){
 const day=dayNumber(date);if(day<model.points[0].day||day>model.points.at(-1).day)throw Error('Choose a date within the displayed range.');
 const existing=model.points.find(p=>p.date===date);if(existing)return existing;
 const details=historyDetails(model,date);let assets=0n,debts=0n,cash=0n,known=0,stale=0,invalid=0,observed=0,oldest=null;
 for(const d of details){if(!d.valid){if(d.entry)invalid++;continue;}const e=d.entry,amount=BigInt(e.amount_minor);known++;if(isDebt(d.account))debts+=amount;else assets+=amount;if(['checking','savings'].includes(d.account.kind))cash+=amount;if(d.stale)stale++;if(e.as_of===date)observed++;if(oldest===null||e.as_of<oldest)oldest=e.as_of;}
 return {date,day,minor:known?checked(model.scope==='account'?assets+debts:assets-debts):null,assets_minor:known?checked(assets):null,debts_minor:known?checked(debts):null,cash_minor:known?checked(cash):null,known,total:details.length,missing:details.length-known,partial:known<details.length,stale,invalid,observed,carried:known-observed,oldest};
}
