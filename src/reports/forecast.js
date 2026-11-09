import {localToday} from '../accounts.js';import {validDay,shiftDay} from './model.js';
function monthOffset(month,offset){const d=new Date(month+'-01T00:00:00Z');d.setUTCMonth(d.getUTCMonth()+offset);return d.toISOString().slice(0,7);}
export function forecastHistoryRange(today=localToday()){validDay(today);const month=today.slice(0,7);return {from:monthOffset(month,-6)+'-01',to:shiftDay(month+'-01',-1)};}
function safe(value){if(value>BigInt(Number.MAX_SAFE_INTEGER)||value<BigInt(Number.MIN_SAFE_INTEGER))throw Error('Forecast exceeds the supported amount range.');return Number(value);}
function mean(values){if(values.some(v=>!Number.isSafeInteger(v)))throw Error('Historical amounts are invalid.');const sum=values.reduce((s,v)=>s+BigInt(v),0n),n=BigInt(values.length),sign=sum<0n?-1n:1n,absolute=sum<0n?-sum:sum;return safe(sign*((absolute+n/2n)/n));}
export function baselineForecast(report,today=localToday()){
 validDay(today);const current=today.slice(0,7),required=[-3,-2,-1].map(n=>monthOffset(current,n)),baseline=required.map(month=>report.current.months.find(m=>m.month===month));
 if(report.invalid_refund_links)return {status:'needs_review',reason:'Review invalid refund links before calculating an estimate.'};
 if(baseline.some(m=>!m||m.partial_window||!m.entry_count&&!m.coverage_confirmed))return {status:'insufficient',reason:'Three consecutive complete calendar months with imported activity or confirmed zero activity are needed.'};
 const income=mean(baseline.map(m=>m.income_minor)),spending=mean(baseline.map(m=>m.spending_minor)),net=safe(BigInt(income)-BigInt(spending));
 return {status:'ready',confirmed:baseline.every(m=>m.coverage_confirmed),from:baseline[0].from,to:baseline[2].to,income_minor:income,spending_minor:spending,net_minor:net,months:[0,1,2].map(n=>({month:monthOffset(current,n),income_minor:income,spending_minor:spending,net_minor:net}))};
}
export function latestMonthlyChange(months){const [previous,latest]=months.slice(-2);if(!latest||!previous||(!latest.entry_count&&!latest.coverage_confirmed)||(!previous.entry_count&&!previous.coverage_confirmed))return null;return {month:latest.month,previous:previous.month,spending_minor:safe(BigInt(latest.spending_minor)-BigInt(previous.spending_minor)),income_minor:safe(BigInt(latest.income_minor)-BigInt(previous.income_minor))};}
