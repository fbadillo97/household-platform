export const ICONS=['shapes','shopping-basket','house','car','utensils','coffee','zap','heart-pulse','graduation-cap','plane','gift','shirt','wrench','baby','paw-print','wallet','landmark','credit-card','chart-no-axes-combined','hand-coins','arrow-left-right','banknote','smartphone','shield-check','briefcase','receipt','calendar-days','files'];
export const TONES=['teal','green','purple','amber','blue','rose','neutral'];
export function normalized(value){return String(value||'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();}
const RULES=[[/grocer|supermarket|food.*store/,'shopping-basket','green'],[/restaurant|dining|takeout/,'utensils','amber'],[/coffee|cafe/,'coffee','amber'],[/mortgage|housing|rent|home/,'house','teal'],[/transport|fuel|gasoline|vehicle|auto|parking/,'car','purple'],[/utilit|electric|hydro|water/,'zap','amber'],[/medical|health|dental|pharma/,'heart-pulse','rose'],[/school|educat|tuition/,'graduation-cap','blue'],[/travel|vacation|flight/,'plane','blue'],[/gift|donat/,'gift','rose'],[/cloth|apparel/,'shirt','purple'],[/repair|mainten/,'wrench','teal'],[/child|baby|daycare/,'baby','rose'],[/pet|veterin/,'paw-print','amber'],[/invest|retire/,'chart-no-axes-combined','green'],[/salary|income|paycheck|payroll/,'banknote','green'],[/transfer|card payment/,'arrow-left-right','neutral'],[/phone|internet|subscription/,'smartphone','blue'],[/insur/,'shield-check','blue']];
export function categoryStyle(name){const rule=RULES.find(([pattern])=>pattern.test(normalized(name)));return {icon:rule?.[1]||'shapes',tone:rule?.[2]||'neutral'};}
export function accountStyle(kind){return {icon:({checking:'landmark',savings:'wallet',credit:'credit-card',loan:'hand-coins',mortgage:'house',investment:'chart-no-axes-combined',asset:'house',other:'wallet'})[kind]||'wallet',tone:({credit:'purple',investment:'green',loan:'amber',mortgage:'amber'})[kind]||'teal'};}
export function initials(name){return String(name||'?').trim().split(/\s+/).slice(0,2).map(s=>Array.from(s)[0]||'').join('').toUpperCase();}
export function resolveVisual(catalog,type,entity={}){
 const preference=catalog.preferences?.find(p=>p.entity_type===type&&p.entity_id===entity.id),base=type==='category'?categoryStyle(entity.name):type==='account'?accountStyle(entity.kind):{icon:entity.kind==='person'?'person':'store',tone:'neutral'};
 let brand=null;
 if(type!=='category'&&preference?.brand_mode!=='none'){
  if(preference?.brand_mode==='brand')brand=catalog.brands?.find(b=>b.key===preference.brand_key)||null;
  else {const names=[entity.institution_name,entity.source_metadata?.institution_name,entity.source_metadata?.institution,entity.name].filter(v=>typeof v==='string').map(normalized);const matches=(catalog.brands||[]).filter(b=>(b.aliases||[]).some(a=>{const alias=normalized(a);return alias&&names.some(n=>type==='payee'?n===alias:(' '+n+' ').includes(' '+alias+' '));}));if(matches.length===1)brand=matches[0];}
 }
 return {...base,customIcon:Boolean(preference?.icon),...(preference?.icon?{icon:preference.icon}:{}),...(preference?.tone?{tone:preference.tone}:{}),brand};
}
export function pngDataUrl(value){return typeof value==='string'&&value.length<=90000&&/^[A-Za-z0-9+/]+={0,2}$/.test(value)&&value.startsWith('iVBORw0KGgo')?'data:image/png;base64,'+value:null;}
