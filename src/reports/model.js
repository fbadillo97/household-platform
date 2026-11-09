import {localToday} from '../accounts.js';
export function validDay(value){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||value<'1900-01-01'||value>'2100-12-31')throw Error('Choose a valid report date.');const d=new Date(value+'T00:00:00Z');if(!Number.isFinite(+d)||d.toISOString().slice(0,10)!==value)throw Error('Choose a valid report date.');return value;}
export function shiftDay(value,days){validDay(value);const d=new Date(value+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+days);return d.toISOString().slice(0,10);}
export function rangeDays(from,to){validDay(from);validDay(to);return Math.round((Date.parse(to+'T00:00:00Z')-Date.parse(from+'T00:00:00Z'))/86400000)+1;}
export function reportRange(preset,today=localToday()){
 validDay(today);const start=new Date(today+'T00:00:00Z');let from= today,to=today;
 if(preset==='month')from=today.slice(0,7)+'-01';
 else if(preset==='last_month'){start.setUTCDate(1);to=shiftDay(start.toISOString().slice(0,10),-1);from=to.slice(0,7)+'-01';}
 else if(preset==='six_months'){start.setUTCDate(1);start.setUTCMonth(start.getUTCMonth()-5);from=start.toISOString().slice(0,10);}
 else if(preset==='year')from=today.slice(0,4)+'-01-01';else if(preset!=='custom')throw Error('Choose a report range.');
 return {from,to};
}
export function reportPayload({from,to,currency,accountIds=[],compare=true},today=localToday()){
 const days=rangeDays(from,to);if(days<1||days>732||to>today)throw Error('Choose a range of up to two years ending today or earlier.');if(!/^[A-Z]{3}$/.test(currency))throw Error('Choose a currency.');
 if(accountIds.length>100||new Set(accountIds).size!==accountIds.length)throw Error('Choose up to 100 distinct accounts.');
 const previous=compare?{compare_to:shiftDay(from,-1),compare_from:shiftDay(from,-days)}:{};
 if(compare)validDay(previous.compare_from);
 return {from,to,currency,account_ids:accountIds,...previous};
}
export function changeLabel(current,previous){if(!Number.isSafeInteger(current)||!Number.isSafeInteger(previous))throw Error('Invalid report amount.');const diff=BigInt(current)-BigInt(previous);if(diff>BigInt(Number.MAX_SAFE_INTEGER)||diff<BigInt(Number.MIN_SAFE_INTEGER))throw Error('Report difference exceeds the supported range.');return Number(diff);}
export function monthLabel(month){return new Intl.DateTimeFormat('en-CA',{month:'short',year:'numeric',timeZone:'UTC'}).format(new Date(month+'-01T00:00:00Z'));}
export function monthScope(row,base,series){return {...base,from:row.from,to:row.to,series};}
