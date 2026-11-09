import React,{createContext,useContext,useState,useEffect,useRef} from 'react';
import {Icon} from './Icon.jsx';import {resolveVisual,initials,pngDataUrl} from './model.js';import './visuals.css';
const Context=createContext({catalog:{brands:[],preferences:[]},error:'',loading:false,reload:async()=>{}});
export function useVisuals(){return useContext(Context);}
export function VisualProvider({secureCall,children}){
 const [catalog,setCatalog]=useState({brands:[],preferences:[]}),[error,setError]=useState(''),[loading,setLoading]=useState(true),alive=useRef(false),request=useRef(0);
 async function reload(){const ticket=++request.current;setLoading(true);setError('');try{const data=await secureCall('visuals_get_catalog');if(alive.current&&ticket===request.current)setCatalog(data);return data;}catch(e){if(alive.current&&ticket===request.current&&e.message!=='Stale session')setError('Images could not be loaded. '+e.message);throw e;}finally{if(alive.current&&ticket===request.current)setLoading(false);}}
 useEffect(()=>{alive.current=true;reload().catch(()=>{});return()=>{alive.current=false;request.current++;};},[]);
 return <Context.Provider value={{catalog,error,loading,reload}}>{children}</Context.Provider>;
}
function Mark({type,entity,small=false}){
 const {catalog}=useVisuals(),visual=resolveVisual(catalog,type,entity),src=pngDataUrl(visual.brand?.png_base64),[broken,setBroken]=useState(null);
 return <span className={'identity-mark tone-'+visual.tone+(small?' identity-small':'')+(type==='payee'?' merchant-mark':'')} aria-hidden="true">{src&&broken!==src?<img src={src} alt="" onError={()=>setBroken(src)}/>:type==='payee'&&entity.name&&entity.kind!=='person'&&!visual.customIcon?<span className="identity-initials">{initials(entity.name)}</span>:<Icon name={visual.icon} size={small?14:20}/>}</span>;
}
export function IdentityLabel({type,entity,children,small=false}){return <span className="identity-label"><Mark type={type} entity={entity} small={small}/><span className="identity-text">{children??entity?.name??'—'}</span></span>;}
export function CategoryLabel({name='Unassigned',id,small=true}){return <IdentityLabel type="category" entity={{id,name}} small={small}/>;}
