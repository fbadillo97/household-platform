const formats=new Map();
// Format integer cents without losing pennies when a large total is divided as a float.
export function formatMoney(minor,currency='CAD'){
 if(!Number.isSafeInteger(minor))throw Error('Invalid money amount');
 let formatter=formats.get(currency);if(!formatter){formatter=new Intl.NumberFormat('en-CA',{style:'currency',currency,minimumFractionDigits:2,maximumFractionDigits:2});formats.set(currency,formatter);}
 const cents=BigInt(minor),absolute=cents<0n?-cents:cents,whole=absolute/100n,fraction=String(absolute%100n).padStart(2,'0');
 const signed=cents<0n?(whole===0n?-0:-whole):whole;
 return formatter.formatToParts(signed).map(part=>part.type==='fraction'?fraction:part.value).join('');
}
