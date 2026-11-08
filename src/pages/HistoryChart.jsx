import React,{useEffect,useRef,useState,useId} from 'react';
export function HistoryChart({model,selected,money,onSelect}){
 const ref=useRef(null),[width,setWidth]=useState(720),id=useId();
 useEffect(()=>{if(!globalThis.ResizeObserver)return;const observer=new ResizeObserver(entries=>{const size=Math.floor(entries[0].contentRect.width);if(size>0)setWidth(Math.max(200,size));});observer.observe(ref.current);return()=>observer.disconnect();},[]);
 const values=model.points.filter(p=>p.minor!==null).map(p=>p.minor);if(!values.length)return null;
 const first=model.points[0],last=model.points.at(-1),left=Math.min(width*.30,115),right=width-16,top=20,bottom=212;
 let min=Math.min(...values),max=Math.max(...values);const nonnegative=min>=0,nonpositive=max<=0;const padding=Math.max(100,(max-min||Math.abs(max))*.08);
 min=Math.max(Number.MIN_SAFE_INTEGER,Math.floor(min-padding));max=Math.min(Number.MAX_SAFE_INTEGER,Math.ceil(max+padding));if(nonnegative)min=Math.max(0,min);if(nonpositive)max=Math.min(0,max);
 const x=day=>first.day===last.day?(left+right)/2:left+(day-first.day)/(last.day-first.day)*(right-left),y=minor=>bottom-(minor-min)/(max-min||1)*(bottom-top);
 const segments=[];let previous=null,current=null;
 for(const p of model.plotted){if(p.minor===null){previous=null;current=null;continue;}if(!previous||previous.coverage_version!==p.coverage_version||previous.partial!==p.partial){current={partial:p.partial,path:`M ${x(p.day)} ${y(p.minor)}`,start:p};segments.push(current);}else current.path+=` H ${x(p.day)} V ${y(p.minor)}`;previous=p;}
 const compact=minor=>new Intl.NumberFormat('en-CA',{style:'currency',currency:model.currency,notation:'compact',maximumFractionDigits:1}).format(minor/100);
 return <div ref={ref} className="history-chart"><svg width="100%" height="260" viewBox={`0 0 ${width} 260`} role="img" aria-labelledby={id+'-title '+id+'-description'} onClick={e=>{const rect=e.currentTarget.getBoundingClientRect(),point=(e.clientX-rect.left)*width/rect.width;const ratio=Math.max(0,Math.min(1,(point-left)/(right-left)));onSelect(new Date(Math.round(first.day+ratio*(last.day-first.day))*86400000).toISOString().slice(0,10));}}>
 <title id={id+'-title'}>{model.scope==='account'?'Saved account balance':'Saved net worth'} history in {model.currency}</title><desc id={id+'-description'}>Stepped values carry saved balances forward. Dashed lines indicate partial coverage; gaps mark a change in which accounts have balances. Use the date controls or data tables for exact values.</desc>
 {[min,Math.round((min+max)/2),max].map((value,i)=><g key={i}><line x1={left} x2={right} y1={y(value)} y2={y(value)} stroke="#dce2d9"/><text x={left-9} y={y(value)+4} textAnchor="end" fill="#456252" fontSize="12">{compact(value)}</text></g>)}
 {min<0&&max>0&&<line x1={left} x2={right} y1={y(0)} y2={y(0)} stroke="#809b8a"/>}
 {segments.map((s,i)=><g key={i}><path d={s.path} fill="none" stroke="#21664e" strokeWidth="2.5" strokeDasharray={s.partial?'5 4':undefined}/><circle cx={x(s.start.day)} cy={y(s.start.minor)} r="3" fill="#21664e"/></g>)}
 {selected.minor!==null&&<g><line x1={x(selected.day)} x2={x(selected.day)} y1={top} y2={bottom} stroke="#596a98" strokeDasharray="3 3"/><circle cx={x(selected.day)} cy={y(selected.minor)} r="5" fill="#4e609c" stroke="#fff" strokeWidth="2"/></g>}
 <text x={left} y="240" fill="#456252" fontSize="12">{first.date}</text>{first.date!==last.date&&<text x={right} y="240" textAnchor="end" fill="#456252" fontSize="12">{last.date}</text>}
 </svg><p className="history-chart-key"><span>Solid: complete saved coverage</span><span>Dashed: partial coverage</span><span>Gaps: coverage changed</span></p>
 {model.sampled&&<small>Chart simplified from {model.points.length.toLocaleString()} saved-date points; bucket extremes and coverage changes are retained. The tables and date inspector use exact saved values.</small>}
 </div>;
}
