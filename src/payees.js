export const PAYEE_KINDS=[['business','Business'],['institution','Institution'],['person','Person'],['other','Other']];
export const payeeKey=value=>value.trim().replace(/\s+/g,' ').toLowerCase();
export function payeeAliases(text){
 const aliases=text.split(/\r?\n/).map(s=>s.trim()).filter(Boolean);
 if(aliases.length>50||aliases.some(s=>s.length>500))throw Error('Use up to 50 aliases, each up to 500 characters.');
 if(new Set(aliases.map(payeeKey)).size!==aliases.length)throw Error('Repeated aliases; use each imported description once.');
 return aliases;
}
