import React from 'react';

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
