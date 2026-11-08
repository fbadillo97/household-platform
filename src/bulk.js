import {tagNames} from './finance.js';
export const BULK_ACTIONS={category:'Set category',payee:'Set payee',review:'Set review status',attention:'Set needs attention',add_tag:'Add tag',remove_tag:'Remove tag',trash:'Move to Trash',restore:'Restore from Trash'};
export const defaultBulkValue=action=>action==='review'?'reviewed':action==='attention'?'true':'';
export function bulkValue(action,input){
 if(action==='payee'){if(!input)throw Error('Choose a payee or Unassigned.');return input==='__unassigned'?null:input;}
 if(action==='category'){if(!input)throw Error('Choose a category or Unassigned.');return input==='__unassigned'?null:input;}
 if(action==='review'){if(!['reviewed','unreviewed'].includes(input))throw Error('Choose a review status.');return input;}
 if(action==='attention'){if(!['true','false'].includes(input))throw Error('Choose an attention status.');return input==='true';}
 if(['add_tag','remove_tag'].includes(action)){const label=input.trim();if(!label||label.length>60)throw Error('Use a tag containing 1–60 characters.');return label;}
 if(['trash','restore'].includes(action))return null;
 throw Error('Choose a bulk action.');
}
export function bulkDescription(action,value,categories,payees=[]){
 if(action==='payee')return 'Set payee to '+(payees.find(p=>p.id===value)?.name||'Unassigned');
 if(action==='category')return 'Set category to '+(categories.find(c=>c.id===value)?.name||'Unassigned');
 if(action==='review')return value==='reviewed'?'Mark as reviewed':'Mark as unreviewed';
 if(action==='attention')return value?'Turn needs attention on':'Turn needs attention off';
 if(action==='add_tag')return `Add tag “${value}” while keeping other tags`;
 if(action==='remove_tag')return `Remove tag “${value}” while keeping other tags`;
 return BULK_ACTIONS[action];
}
export function bulkPreview(row,action,value,categories,payees=[]){
 if(action==='payee')return `${payees.find(p=>p.id===row.payee_id)?.name||'Unassigned'} → ${payees.find(p=>p.id===value)?.name||'Unassigned'}`;
 if(action==='category')return `${categories.find(c=>c.id===row.category_id)?.name||'Unassigned'} → ${categories.find(c=>c.id===value)?.name||'Unassigned'}`;
 if(action==='review')return `${row.review_status==='reviewed'?'Reviewed':'Unreviewed'} → ${value==='reviewed'?'Reviewed':'Unreviewed'}`;
 if(action==='attention')return `${row.needs_attention?'Needs attention':'No attention flag'} → ${value?'Needs attention':'No attention flag'}`;
 if(['add_tag','remove_tag'].includes(action)){
  const tags=tagNames(row),key=value.toLocaleLowerCase();
  const next=action==='add_tag'?(tags.some(t=>t.toLocaleLowerCase()===key)?tags:[...tags,value]):tags.filter(t=>t.toLocaleLowerCase()!==key);
  return `${tags.join(', ')||'No tags'} → ${next.join(', ')||'No tags'}`;
 }
 return action==='trash'?'Active → Trash (recoverable)':'Trash → Active';
}
