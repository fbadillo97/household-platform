import Papa from 'papaparse';
export function parseCSV(text){
 if(new TextEncoder().encode(text).length>1000000)throw Error('CSV must be at most 1 MB');
 const parsed=Papa.parse(text.replace(/^\uFEFF/,''),{header:true,skipEmptyLines:'greedy',dynamicTyping:false});
 if(JSON.stringify(parsed.meta.fields)!==JSON.stringify(['date','description','amount']))throw Error('Expected date,description,amount headers in that order');
 if(parsed.errors.some(e=>e.type==='Quotes'))throw Error('CSV has malformed quotes');
 if(!parsed.data.length||parsed.data.length>5000)throw Error('Select a CSV with 1–5000 rows');
 const badRows=new Set(parsed.errors.map(e=>e.row));
 return parsed.data.map((row,index)=>({...row,...(badRows.has(index)?{parse_error:'Invalid column count'}:{})}));
}
export function defaultSelection(batch){return batch.rows.filter(r=>!r.error&&!r.duplicate).map(r=>r.id);}
export function commitSelection(batch,selected){return {id:batch.id,row_ids:selected,duplicate_ids:batch.rows.filter(r=>r.duplicate&&selected.includes(r.id)).map(r=>r.id)};}
