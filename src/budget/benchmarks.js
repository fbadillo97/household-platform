import {safe} from './model.js';
export const STATCAN_SOURCES={income:{table_id:'11-10-0223-01',product_id:'11100223',title:'Household spending by household income quintile, Canada, regions and provinces',url:'https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1110022301',supported_dimensions:['GEO','Before-tax household income quintile']}};
export const STATCAN_GUIDE='https://www150.statcan.gc.ca/n1/pub/62f0026m/62f0026m2025001-eng.htm';
function decimalCents(value){const text=String(value).trim();if(!/^\d+(\.\d{1,2})?$/.test(text))throw Error('Unsupported annual benchmark value.');const [whole,fraction='']=text.split('.');return BigInt(whole)*100n+BigInt(fraction.padEnd(2,'0'));}
export function monthlyBenchmark(record,currency){
 if(!record||record.currency!==currency||record.value_annual===null||['F','x','..','...'].includes(record.status)||record.suppressed)return null;
 if(record.unit!=='CAD/year'||!record.cohort_label||!record.reference_year||!record.source_url)throw Error('Benchmark provenance is incomplete.');
 const annual=decimalCents(record.value_annual);return {amount_minor:safe((annual+6n)/12n),reference_year:record.reference_year,cohort_label:record.cohort_label,source_url:record.source_url,caution:['E','p'].includes(record.status),basis:'Annual average ÷ 12; not inflation adjusted'};
}
// Adapter consumes official CSV records after parsing. It requires explicit dimension
// selection and a pre-reviewed category mapping. No inferred combined peer cohort.
export function selectStatcanRows(rows,{sourceKey='income',referenceYear,dimensions,expenditureField,statisticField,statisticValue,cohortLabel,retrievedAt}){
 const source=STATCAN_SOURCES[sourceKey];if(!source)throw Error('Unrecognized Statistics Canada source.');
 if(!/^\d{4}$/.test(String(referenceYear))||!cohortLabel||!retrievedAt||!expenditureField||!statisticField||!statisticValue||!dimensions||!Object.keys(dimensions).length)throw Error('Select an explicit source year, cohort and statistic.');
 for(const key of Object.keys(dimensions))if(!source.supported_dimensions.includes(key))throw Error('This source does not support that combined household profile.');
 for(const key of source.supported_dimensions)if(!dimensions[key])throw Error('Select every cohort dimension explicitly.');
 const result=[],seen=new Set();
 for(const row of rows){if(String(row.REF_DATE)!==String(referenceYear))continue;if(!Object.entries(dimensions).every(([key,value])=>row[key]===value)||row[statisticField]!==statisticValue)continue;
  if(row.UOM!=='Dollars'||row.SCALAR_FACTOR!=='units')throw Error('Unsupported Statistics Canada unit or scale.');const label=row[expenditureField];if(!label)throw Error('Missing expenditure label.');if(seen.has(label))throw Error('Ambiguous duplicate benchmark series.');seen.add(label);
  const status=String(row.STATUS||'').trim(),raw=String(row.VALUE??'').trim();const usable=/^\d+(\.\d{1,2})?$/.test(raw)&&['','E','p','r'].includes(status);
  result.push({source_table:source.table_id,source_url:source.url,reference_year:Number(referenceYear),retrieved_at:retrievedAt,cohort_label:cohortLabel,dimensions:{...dimensions},expenditure_label:label,value_annual:usable?raw:null,unit:'CAD/year',currency:'CAD',status,vector:row.VECTOR||null,coordinate:row.COORDINATE||null,suppressed:!usable});
 }
 if(!result.length)throw Error('No published rows match this cohort and year.');return result;
}
export function categoryBenchmarks(records,mappings,currency){
 const result=new Map(),usedSeries=new Set();
 for(const mapping of mappings){const matches=records.filter(r=>(mapping.expenditure_label?r.expenditure_label===mapping.expenditure_label:r.vector===mapping.vector)&&r.source_table===mapping.source_table&&r.reference_year===mapping.reference_year&&(!mapping.cohort_label||r.cohort_label===mapping.cohort_label));if(matches.length>1)throw Error('Choose one published cohort for comparison.');const record=matches[0];if(!record)continue;if(!mapping.expenditure_label&&!mapping.vector)throw Error('Choose a benchmark expenditure series.');
  const key=[record.source_table,record.reference_year,record.cohort_label,record.vector].join(':');if(usedSeries.has(key)||result.has(mapping.category_id))throw Error('A benchmark series or category has overlapping mappings.');usedSeries.add(key);
  result.set(mapping.category_id,{...monthlyBenchmark(record,currency),record,comparable:mapping.comparable===true,note:mapping.note||''});
 }
 return result;
}
