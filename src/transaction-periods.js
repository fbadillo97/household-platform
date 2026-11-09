import {localToday} from './accounts.js';
export const TRANSACTION_PERIODS=[['all','All time'],['month','This month to date'],['last_month','Last month'],['specific_month','Specific month'],['quarter','This quarter to date'],['last_quarter','Last quarter'],['three_months','Last 3 months'],['six_months','Last 6 months'],['year','This year to date'],['last_year','Last year'],['one_year','Last 12 months'],['two_years','Last 2 years'],['five_years','Last 5 years'],['custom','Custom dates']];
function date(value){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))throw Error('Choose a valid date');const d=new Date(value+'T00:00:00Z');if(!Number.isFinite(+d)||iso(d)!==value)throw Error('Choose a valid date');return d;}
const iso=d=>d.toISOString().slice(0,10);
function shift(value,days){const d=date(value);d.setUTCDate(d.getUTCDate()+days);return iso(d);}
function monthsAgo(value,months){const d=date(value),day=d.getUTCDate();d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth()-months);const last=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0)).getUTCDate();d.setUTCDate(Math.min(day,last));return iso(d);}
export function transactionPeriodRange(preset,today=localToday(),month=''){
 date(today);let from='',to='';const currentMonth=today.slice(0,7)+'-01';
 if(preset==='all'||preset==='custom')return {from,to};
 if(preset==='specific_month'){if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))throw Error('Choose a month');const start=date(month+'-01');return {from:iso(start),to:iso(new Date(Date.UTC(start.getUTCFullYear(),start.getUTCMonth()+1,0)))};}
 if(preset==='month'){from=currentMonth;to=today;}
 else if(preset==='last_month'){to=shift(currentMonth,-1);from=to.slice(0,7)+'-01';}
 else if(preset==='quarter'||preset==='last_quarter'){const d=date(today);d.setUTCDate(1);d.setUTCMonth(Math.floor(d.getUTCMonth()/3)*3);from=iso(d);to=today;if(preset==='last_quarter'){to=shift(from,-1);from=monthsAgo(from,3);}}
 else if(preset==='year'){from=today.slice(0,4)+'-01-01';to=today;}
 else if(preset==='last_year'){const year=Number(today.slice(0,4))-1;from=year+'-01-01';to=year+'-12-31';}
 else {const months={three_months:3,six_months:6,one_year:12,two_years:24,five_years:60}[preset];if(!months)throw Error('Choose a date period');from=shift(monthsAgo(today,months),1);to=today;}
 return {from,to};
}
export function selectedTransactionPeriod(view,month){if(month)return 'specific_month';return TRANSACTION_PERIODS.some(([id])=>id===view.datePreset)?view.datePreset:view.columns.dateFrom||view.columns.dateTo?'custom':'all';}
