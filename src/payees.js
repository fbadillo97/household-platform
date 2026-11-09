export const PAYEE_KINDS=[['business','Business'],['institution','Institution'],['person','Person'],['other','Other']];
export const payeeKey=value=>value.trim().replace(/\s+/g,' ').toLowerCase();
export function payeeAliases(text){
 const aliases=text.split(/\r?\n/).map(s=>s.trim()).filter(Boolean);
 if(aliases.length>50||aliases.some(s=>s.length>500))throw Error('Use up to 50 aliases, each up to 500 characters.');
 if(new Set(aliases.map(payeeKey)).size!==aliases.length)throw Error('Repeated aliases; use each imported description once.');
 return aliases;
}
export function payeeDirectory(payees,{query='',kind='',tag='',archived=false,sort='name',direction='asc'}={}){
 const q=query.trim().toLowerCase();
 const rows=payees.filter(p=>!!p.archived_at===archived&&(!kind||p.kind===kind)&&(!tag||(tag==='__untagged'?!(p.tags||[]).length:(p.tags||[]).some(t=>t.id===tag)))&&[p.name,...(p.aliases||[]),...(p.tags||[]).map(t=>t.name)].join(' ').toLowerCase().includes(q));
 return rows.sort((a,b)=>{const av=sort==='count'?a.transaction_count||0:sort==='last'?a.last_transaction||'':sort==='kind'?a.kind:a.name;const bv=sort==='count'?b.transaction_count||0:sort==='last'?b.last_transaction||'':sort==='kind'?b.kind:b.name;const n=typeof av==='number'?av-bv:String(av).localeCompare(String(bv),'en',{sensitivity:'base',numeric:true});return (direction==='desc'?-n:n)||a.name.localeCompare(b.name)||a.id.localeCompare(b.id);});
}
