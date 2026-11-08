export const isTransfer=row=>['transfer','credit_card_payment'].includes(row.flow_type);
export const flowLabel=type=>type==='credit_card_payment'?'Credit card payment':type==='transfer'?'Transfer':'Regular transaction';
export function summarizeRows(rows){
 return rows.reduce((sum,row)=>{if(!Number.isSafeInteger(row.amount_minor))throw Error('Invalid stored amount');sum.count++;if(isTransfer(row))return sum;if(row.amount_minor>0)sum.inflow+=row.amount_minor;else sum.outflow-=row.amount_minor;sum.net+=row.amount_minor;return sum;},{count:0,inflow:0,outflow:0,net:0});
}
export function tagNames(row){return (row.tags_override??row.source_data?.tags??[]).map(t=>typeof t==='string'?t:t.name||t.id).filter(Boolean);}
export function filterRows(rows,{accountId='',month='',query=''},categories){
 const names=new Map(categories.map(c=>[c.id,c.name]));const q=query.trim().toLocaleLowerCase();
 return rows.filter(t=>(!accountId||t.account_id===accountId)&&(!month||t.date.startsWith(month))&&(!q||[t.description,names.get(t.category_id)||'',...tagNames(t)].join(' ').toLocaleLowerCase().includes(q)));
}
export const EMPTY_COLUMN_FILTERS={dateFrom:'',dateTo:'',description:'',category:'',minAmount:'',maxAmount:'',tags:''};
export function amountFilterMinor(value){
 if(value.trim()==='')return null;
 const text=value.trim();if(!/^[+-]?\d+(\.\d{1,2})?$/.test(text))throw Error('Use signed amounts with at most two decimal places');
 const negative=text.startsWith('-');const [whole,fraction='']=text.replace(/^[+-]/,'').split('.');
 const cents=Number(whole)*100+Number(fraction.padEnd(2,'0'));
 if(!Number.isSafeInteger(cents)||cents>100000000000)throw Error('Amount filter is outside the supported range');
 return negative?-cents:cents;
}
export function ledgerPayload({accountId='',month='',query='',view}){
 const f=view.columns;const min=amountFilterMinor(f.minAmount),max=amountFilterMinor(f.maxAmount);
 if(min!==null&&max!==null&&min>max)throw Error('Minimum amount must not exceed maximum amount');
 if(f.dateFrom&&f.dateTo&&f.dateFrom>f.dateTo)throw Error('Start date must not follow end date');
 return {trash_only:!!view.trashOnly,review:view.review||'',flow:view.flow||'',account_id:accountId||null,month,query:query.trim(),description:f.description.trim(),tags:f.tags.trim(),category_id:f.category||null,date_from:f.dateFrom||null,date_to:f.dateTo||null,min_minor:min,max_minor:max,sort:view.sort,direction:view.direction,offset:view.offset,limit:50};
}
