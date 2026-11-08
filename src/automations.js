import {formatMoney} from './money.js';
const name=(rows,id,empty='Unassigned')=>id?(rows.find(row=>row.id===id)?.name||'Unavailable record'):empty;
export function automationStatement(rule,{payees=[],accounts=[],categories=[]}={}){
 if(rule.kind==='alias')return `Recognize “${rule.description}” as ${name(payees,rule.payee_id)}.`;
 const c=rule.conditions||{},a=rule.actions||{},when=[],then=[];
 if(c.payee_id)when.push(`the payee is ${name(payees,c.payee_id)}`);
 if(c.account_id)when.push(`the account is ${name(accounts,c.account_id)}`);
 if(c.description_contains)when.push(`the imported description contains “${c.description_contains}”`);
 const money=value=>formatMoney(value,c.currency||'CAD');
 if(c.amount_min_minor!=null&&c.amount_max_minor!=null&&c.amount_min_minor===c.amount_max_minor)when.push(`the signed amount is ${money(c.amount_min_minor)} ${c.currency}`);
 else{if(c.amount_min_minor!=null)when.push(`the signed amount is at least ${money(c.amount_min_minor)} ${c.currency}`);if(c.amount_max_minor!=null)when.push(`the signed amount is at most ${money(c.amount_max_minor)} ${c.currency}`);}
 if(c.currency&&c.amount_min_minor==null&&c.amount_max_minor==null)when.push(`the currency is ${c.currency}`);
 if(Object.hasOwn(a,'payee_id'))then.push(`assign payee ${name(payees,a.payee_id)}`);
 if(Object.hasOwn(a,'category_id'))then.push(`set category to ${name(categories,a.category_id)}`);
 if(a.add_tags)then.push(`add ${a.add_tags.length===1?'tag':'tags'} ${a.add_tags.map(t=>`“${t}”`).join(', ')}`);
 if(a.review_status)then.push(`mark ${a.review_status}`);
 if(Object.hasOwn(a,'needs_attention'))then.push(a.needs_attention?'flag for attention':'clear the attention flag');
 return `When ${when.join(' and ')}, ${then.join(' and ')}.`;
}
export function automationChange(values,{payees=[],categories=[]}={}){
 const parts=[];
 if(Object.hasOwn(values,'payee_id'))parts.push('Payee: '+name(payees,values.payee_id));
 if(Object.hasOwn(values,'category_id'))parts.push('Category: '+name(categories,values.category_id));
 if(Object.hasOwn(values,'tags_override'))parts.push('Tags: '+(values.tags_override===null?'Imported tags':values.tags_override.join(', ')||'None'));
 if(values.review_status)parts.push(values.review_status==='reviewed'?'Reviewed':'Unreviewed');
 if(Object.hasOwn(values,'needs_attention'))parts.push(values.needs_attention?'Needs attention':'No attention flag');
 return parts.join(' · ')||'No field changes';
}
