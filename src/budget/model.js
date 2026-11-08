// Exact minor-unit reference calculations. Production RPC must implement the same rules
// against the complete ledger, not a browser sample or dashboard's latest-500 rows.
export const REFUND_TIMING={received:'Month received',purchase:'Original purchase month'};
export const ROLLOVER_MODES={reset:'Reset monthly',unused:'Carry unused money forward'};
export function monthKey(value){if(typeof value!=='string'||!/^\d{4}-(0[1-9]|1[0-2])$/.test(value)||Number(value.slice(0,4))<1900||Number(value.slice(0,4))>2100)throw Error('Choose a month between 1900 and 2100.');return value;}
export function nextMonth(value){monthKey(value);const [year,month]=value.split('-').map(Number);return monthKey(`${month===12?year+1:year}-${String(month===12?1:month+1).padStart(2,'0')}`);}
export function previousMonth(value){monthKey(value);const [year,month]=value.split('-').map(Number);return monthKey(`${month===1?year-1:year}-${String(month===1?12:month-1).padStart(2,'0')}`);}
export function minor(value){if(!Number.isSafeInteger(value))throw Error('Money must be a safe integer in cents.');return BigInt(value);}
export function safe(value){const result=Number(value);if(!Number.isSafeInteger(result))throw Error('Money total exceeds the supported range.');return result;}
export function parseAmount(text){if(typeof text!=='string'||!/^\d+(\.\d{1,2})?$/.test(text.trim()))throw Error('Enter a non-negative amount with at most two decimal places.');const [whole,fraction='']=text.trim().split('.');return safe(BigInt(whole)*100n+BigInt(fraction.padEnd(2,'0')));}
export function amountInput(value){const cents=minor(value);if(cents<0n)throw Error('Planned amounts cannot be negative.');return `${cents/100n}.${String(cents%100n).padStart(2,'0')}`;}
const active=t=>!t.deleted_at;
const regular=t=>!['transfer','credit_card_payment'].includes(t.flow_type);
function transactionMonth(t){if(typeof t.date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(t.date))throw Error('Transaction date is missing.');return monthKey(t.date.slice(0,7));}
export function validateRefundLinks(transactions,links){
 const byId=new Map(transactions.map(t=>[t.id,t]));if(byId.size!==transactions.length)throw Error('Duplicate transaction context.');
 const purchases=new Map(),refunds=new Map(),pairs=new Set(),issues=[],valid=[];
 for(const link of links){const p=byId.get(link.purchase_id),r=byId.get(link.refund_id);if(!p||!r)throw Error('Refund context is incomplete; reload the complete linked records.');
  const value=minor(link.amount_minor);if(value<=0n||p.id===r.id||minor(p.amount_minor)>=0n||minor(r.amount_minor)<=0n||p.currency!==r.currency||!regular(p)||!regular(r))throw Error('Refund must link a regular credit to a purchase in the same currency.');
  const pair=p.id+':'+r.id;if(pairs.has(pair))throw Error('Duplicate purchase/refund link.');pairs.add(pair);
  purchases.set(p.id,(purchases.get(p.id)||0n)+value);refunds.set(r.id,(refunds.get(r.id)||0n)+value);
  if(purchases.get(p.id)>-minor(p.amount_minor)||refunds.get(r.id)>minor(r.amount_minor))throw Error('Refund allocation exceeds the purchase or credit.');
  if(!active(p)||!active(r)){issues.push({id:link.id,message:'A linked record is in Trash. Restore it or unlink this refund.'});continue;}
  valid.push({...link,purchase:p,refund:r});
 }
 return {valid,issues,knownRefundIds:new Set(links.map(l=>l.refund_id))};
}
export function spendingForMonth({month,currency,transactions,refundLinks=[],lines,refundTiming}){
 monthKey(month);if(!Object.hasOwn(REFUND_TIMING,refundTiming))throw Error('Choose how cross-month refunds affect your budget.');
 const {valid,issues,knownRefundIds}=validateRefundLinks(transactions,refundLinks),byCategory=new Map(),allocated=new Map();let unallocatedCredits=0n;
 const roles=new Map(lines.map(l=>[l.category_id,l.role]));if(roles.size!==lines.length)throw Error('A category can appear only once in a monthly plan.');
 const add=(category,amount)=>byCategory.set(category,(byCategory.get(category)||0n)+amount);
 for(const link of valid){allocated.set(link.refund_id,(allocated.get(link.refund_id)||0n)+minor(link.amount_minor));const assignedMonth=transactionMonth(refundTiming==='purchase'?link.purchase:link.refund);
  if(link.purchase.currency===currency&&assignedMonth===month){if(roles.get(link.purchase.category_id)==='income')throw Error('A refunded purchase category is planned as income; correct the category or plan');add(link.purchase.category_id,-minor(link.amount_minor));}}
 for(const t of transactions){if(!active(t)||!regular(t)||t.currency!==currency||transactionMonth(t)!==month)continue;const value=minor(t.amount_minor),role=roles.get(t.category_id);
  if(value<0n)add(t.category_id,role==='income'?value:-value);
  else if(value>0n){const remainder=value-(allocated.get(t.id)||0n);if(role==='income'&&!knownRefundIds.has(t.id))add(t.category_id,remainder);else unallocatedCredits+=remainder;}
 }
 let expense=0n,income=0n;const categories=[];
 for(const [category_id,value] of byCategory){const role=roles.get(category_id)||'expense';if(role==='income')income+=value;else expense+=value;categories.push({category_id,role,actual_minor:safe(value),unbudgeted:!roles.has(category_id)});}
 return {categories,expense_minor:safe(expense),income_minor:safe(income),unallocated_credits_minor:safe(unallocatedCredits),issues};
}
export function categoryBalance({planned_minor,spent_minor,opening_minor=0,mode='reset',cap_minor=null,coverage_complete=false}){
 if(!Object.hasOwn(ROLLOVER_MODES,mode))throw Error('Unknown rollover mode.');const planned=minor(planned_minor),spent=minor(spent_minor),cap=cap_minor===null?null:minor(cap_minor);if(planned<0n||cap!==null&&cap<0n)throw Error('Budget and rollover cap must be non-negative.');
 let opening=mode==='reset'?0n:opening_minor===null?null:minor(opening_minor);if(opening!==null&&opening<0n)throw Error('Unused rollover cannot start negative.');if(opening!==null&&cap!==null&&opening>cap)opening=cap;
 const available=opening===null?null:planned+opening,remaining=available===null?null:available-spent;
 let carry=mode==='reset'?0n:!coverage_complete||remaining===null?null:remaining>0n?remaining:0n;if(carry!==null&&cap!==null&&carry>cap)carry=cap;
 return {opening_minor:opening===null?null:safe(opening),available_minor:available===null?null:safe(available),remaining_minor:remaining===null?null:safe(remaining),carry_out_minor:carry===null?null:safe(carry),provisional:!coverage_complete};
}
export function calculateBudget({month,currency,plans,transactions,refundLinks=[],refundTiming}){
 monthKey(month);if(!/^[A-Z]{3}$/.test(currency))throw Error('Choose a currency.');const ordered=plans.filter(p=>p.currency===currency&&p.month<=month).sort((a,b)=>a.month.localeCompare(b.month));
 if(!ordered.length||ordered.at(-1).month!==month)throw Error('This month has no saved plan.');const seen=new Set();let prior=null,carry=new Map(),answer;const seenCategories=new Set();
 for(const plan of ordered){monthKey(plan.month);if(seen.has(plan.month))throw Error('Duplicate monthly plan.');seen.add(plan.month);
  const consecutive=prior&&nextMonth(prior)===plan.month;const amounts=spendingForMonth({month:plan.month,currency,transactions,refundLinks,lines:plan.lines,refundTiming});const actual=new Map(amounts.categories.map(c=>[c.category_id,c]));const nextCarry=new Map();let totalPlanned=0n,totalIncomePlan=0n,totalRemaining=0n,knownRemaining=true;
  const lines=plan.lines.map(line=>{if(!['income','expense'].includes(line.role))throw Error('Choose income or expense.');if(minor(line.planned_minor)<0n)throw Error('Budget must be non-negative.');const spent=actual.get(line.category_id)?.actual_minor||0;
   if(line.role==='income'){if(line.rollover_mode!=='reset'||line.cap_minor!==null&&line.cap_minor!==undefined)throw Error('Income categories do not roll over.');totalIncomePlan+=minor(line.planned_minor);return {...line,actual_minor:spent,remaining_minor:safe(minor(line.planned_minor)-minor(spent)),opening_minor:0,available_minor:line.planned_minor,carry_out_minor:0,provisional:!plan.coverage_complete};}
   // A category starts with zero at the plan's explicit anchor; gaps never silently reset its carry.
   const opening=prior===null?0:!consecutive?null:carry.has(line.category_id)?carry.get(line.category_id):seenCategories.has(line.category_id)?null:0;
   const balance=categoryBalance({planned_minor:line.planned_minor,spent_minor:spent,opening_minor:opening,mode:line.rollover_mode,cap_minor:line.cap_minor??null,coverage_complete:!!plan.coverage_complete});nextCarry.set(line.category_id,balance.carry_out_minor);totalPlanned+=minor(line.planned_minor);if(balance.remaining_minor===null)knownRemaining=false;else totalRemaining+=minor(balance.remaining_minor);return {...line,actual_minor:spent,...balance};});
  const unbudgeted=amounts.categories.filter(c=>c.unbudgeted&&c.role==='expense');const unbudgetedTotal=unbudgeted.reduce((sum,c)=>sum+minor(c.actual_minor),0n);totalRemaining-=unbudgetedTotal;
  answer={month:plan.month,currency,coverage_complete:!!plan.coverage_complete,lines,unbudgeted,...amounts,planned_expense_minor:safe(totalPlanned),planned_income_minor:safe(totalIncomePlan),remaining_minor:knownRemaining?safe(totalRemaining):null};for(const line of plan.lines)seenCategories.add(line.category_id);carry=nextCarry;prior=plan.month;
 }
 return answer;
}
export function copyPlan(plan,targetMonth){monthKey(targetMonth);if(targetMonth<=plan.month)throw Error('Copy a plan into a later month.');return {month:targetMonth,currency:plan.currency,coverage_complete:false,lines:plan.lines.map(({category_id,role,planned_minor,rollover_mode,cap_minor})=>({category_id,role,planned_minor,rollover_mode,cap_minor:cap_minor??null}))};}
