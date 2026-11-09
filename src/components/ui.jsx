import React from 'react';
import {EmptyIllustration} from '../visuals/EmptyIllustration.jsx';

/** Shared presentation primitives. Business logic belongs in calling modules. */
export function Panel({as:Tag='section',className='',children,...rest}){
 return <Tag className={['panel',className].filter(Boolean).join(' ')} {...rest}>{children}</Tag>;
}
export function SectionHeading({title,detail,actions,className=''}){
 return <div className={['section-head',className].filter(Boolean).join(' ')}><div><h2>{title}</h2>{detail&&<p className="section-description">{detail}</p>}</div>{actions&&<div className="section-actions">{actions}</div>}</div>;
}
export function InlineNotice({kind='error',children}){
 return <p className={'inline-notice inline-notice-'+kind} role={kind==='error'?'alert':'status'}>{children}</p>;
}

export function EmptyState({title,detail,children,illustration='transactions'}){
 return <div className="empty-state">{illustration&&<EmptyIllustration kind={illustration}/>}<h3>{title}</h3>{detail&&<p>{detail}</p>}{children}</div>;
}
export function MetricCard({label,value,detail}){
 return <article><span>{label}</span><strong>{value}</strong>{detail&&<small>{detail}</small>}</article>;
}
