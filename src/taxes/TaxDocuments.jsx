import {Icon} from '../visuals/Icon.jsx';
import React,{useState,useRef,useEffect} from 'react';
import {receiptMetadata} from '../receipts.js';
import {linkedDocuments} from './model.js';
export function TaxDocuments({kind,id,data,secureCall,documentStorage,reload,disabled=false,readOnly=false}){
 const alive=useRef(true),url=useRef(null);
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[selected,setSelected]=useState(''),[download,setDownload]=useState(null);
 useEffect(()=>{alive.current=true;return()=>{alive.current=false;if(url.current)URL.revokeObjectURL(url.current);};},[]);
 const documents=linkedDocuments(data,kind,id),available=data.documents.filter(d=>d.state==='ready'&&!documents.some(v=>v.id===d.id));
 async function act(work){setBusy(true);setError('');try{await work();}catch(e){if(alive.current&&e.message!=='Stale session')setError(e.message);}finally{if(alive.current)setBusy(false);}}
 async function upload(file){if(!file)return;await act(async()=>{
  const metadata=await receiptMetadata(file);if(!alive.current)return;
  const result=await secureCall('tax_prepare_document',{year:data.year,target_kind:kind,target_id:id,...metadata});if(!alive.current)return;
  if(!result.already_exists){try{await documentStorage('upload',result.object_path,file,metadata.mime_type);}catch(e){if(String(e.statusCode||e.status)!=='409')throw e;}
   if(!alive.current)return;await secureCall('tax_finish_document',{id:result.id,revision:result.revision});}
  if(alive.current)await reload();
 });}
 async function open(document){await act(async()=>{const blob=await documentStorage('download',document.object_path);if(!alive.current)return;if(url.current)URL.revokeObjectURL(url.current);url.current=URL.createObjectURL(new Blob([blob],{type:document.mime_type}));setDownload({url:url.current,name:document.filename});});}
 return <section className="tax-documents" aria-label="Supporting documents"><h3>Supporting documents</h3>
 {error&&<p className="error" role="alert">{error}</p>}
 {documentStorage&&!readOnly&&<label className="tax-upload">Attach PDF or image · up to 10 MB<input type="file" accept="application/pdf,image/jpeg,image/png,image/webp" disabled={busy||disabled} onChange={e=>{const file=e.target.files?.[0];e.target.value='';upload(file);}}/></label>}
 {documents.length?<ul>{documents.map(d=><li key={d.id}><span>{d.filename}{d.state==='pending'&&<small> · Upload incomplete; retry the same file</small>}</span><div className="tax-actions">{d.state==='ready'&&documentStorage&&<button type="button" className="secondary" disabled={busy||disabled} onClick={()=>open(d)}><Icon name="download"/>Download</button>}<button type="button" className="text-button" disabled={busy||disabled||readOnly} onClick={()=>act(async()=>{await secureCall('tax_unlink_document',{target_kind:kind,target_id:id,document_id:d.id});if(alive.current)await reload();})}>Unlink</button></div></li>)}</ul>:<p className="tax-muted">No documents linked.</p>}
 {download&&<a href={download.url} download={download.name}>Save {download.name}</a>}
 {!readOnly&&!!available.length&&<form className="tax-doc-link" onSubmit={e=>{e.preventDefault();act(async()=>{await secureCall('tax_link_document',{target_kind:kind,target_id:id,document_id:selected});if(alive.current){setSelected('');await reload();}});}}><label>Use an existing document<select required value={selected} disabled={busy||disabled} onChange={e=>setSelected(e.target.value)}><option value="">Choose document</option>{available.map(d=><option key={d.id} value={d.id}>{d.filename}</option>)}</select></label><button disabled={busy||disabled||!selected}>Link</button></form>}
 </section>;
}
