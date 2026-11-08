export function summarizeRows(rows){
 return rows.reduce((sum,row)=>{if(!Number.isSafeInteger(row.amount_minor))throw Error('Invalid stored amount');sum.count++;if(row.amount_minor>0)sum.inflow+=row.amount_minor;else sum.outflow-=row.amount_minor;sum.net+=row.amount_minor;return sum;},{count:0,inflow:0,outflow:0,net:0});
}
export function tagNames(row){return (row.source_data?.tags||[]).map(t=>typeof t==='string'?t:t.name||t.id).filter(Boolean);}
export function filterRows(rows,{accountId='',month='',query=''},categories){
 const names=new Map(categories.map(c=>[c.id,c.name]));const q=query.trim().toLocaleLowerCase();
 return rows.filter(t=>(!accountId||t.account_id===accountId)&&(!month||t.date.startsWith(month))&&(!q||[t.description,names.get(t.category_id)||'',...tagNames(t)].join(' ').toLocaleLowerCase().includes(q)));
}
