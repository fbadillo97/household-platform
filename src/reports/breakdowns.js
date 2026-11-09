import {changeLabel} from './model.js';
const checked=n=>{if(!Number.isSafeInteger(n))throw Error('Report amount exceeds the supported range.');return BigInt(n);};
const percentage=(n,d)=>Number((n*1000n+(n<0n?-d/2n:d/2n))/d)/10;
export function savingsRate(income,surplus){const i=checked(income),s=checked(surplus);return i>0n?percentage(s,i):null;}
export function categoryBreakdown(rows,series){
 const key=series+'_minor',sorted=rows.map(r=>({...r,value:r[key]})).sort((a,b)=>b.value-a.value||a.name.localeCompare(b.name)||String(a.category_id).localeCompare(String(b.category_id)));
 const positive=sorted.filter(r=>r.value>0),total=positive.reduce((s,r)=>s+checked(r.value),0n);
 const ranked=sorted.map(r=>({...r,share:r.value>0?percentage(checked(r.value),total):null}));
 const head=ranked.filter(r=>r.value>0).slice(0,7),rest=positive.slice(7),other=rest.reduce((s,r)=>s+checked(r.value),0n);
 const slices=[...head.map(r=>({...r,fraction:Number(checked(r.value)*1000000000n/total)/1e9})),...(other?[{category_id:'other',name:'Other categories',other:true,fraction:Number(other*1000000000n/total)/1e9,share:percentage(other,total)}]:[])];
 return {ranked,slices,hasAdjustments:ranked.some(r=>r.value<0)};
}
export function categoryChanges(current,previous,series){
 const key=series+'_minor',id=r=>r.category_id??'unassigned',before=new Map(previous.map(r=>[id(r),r])),now=new Map(current.map(r=>[id(r),r]));
 return [...new Set([...before.keys(),...now.keys()])].map(k=>{const a=now.get(k),b=before.get(k),value=a?.[key]??0,prior=b?.[key]??0,delta=changeLabel(value,prior);
 return {...a||b,current:value,previous:prior,delta,percent:prior>0&&value>=0?percentage(checked(delta),checked(prior)):null,baseline:prior===0?'No prior amount':prior<0||value<0?'Net credit / correction comparison':null};
 }).filter(r=>r.delta!==0).sort((a,b)=>Math.abs(b.delta)-Math.abs(a.delta)||a.name.localeCompare(b.name));
}
