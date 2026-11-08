"""Public Statistics Canada snapshot builder; no household information is accepted or sent.
Run from repository root with Python 3. Standard library only. Optional --archive reuses
an already-downloaded official ZIP for reproducible local preparation.
"""
import argparse,csv,hashlib,io,json,re,urllib.request,zipfile
from datetime import datetime,timezone
from pathlib import Path
URL='https://www150.statcan.gc.ca/n1/tbl/csv/11100223-eng.zip'
TABLE_URL='https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1110022301'
LABELS=['Food purchased from stores','Food purchased from restaurants','Clothing and accessories','Recreation']
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--archive');parser.add_argument('--output',default='src/budget/statcan-baseline.json');args=parser.parse_args()
 if args.archive:data=Path(args.archive).read_bytes()
 else:
  with urllib.request.urlopen(URL,timeout=60) as response:data=response.read(30_000_001)
 if len(data)>30_000_000:raise ValueError('Archive exceeds preparation size limit')
 z=zipfile.ZipFile(io.BytesIO(data));info=z.getinfo('11100223.csv')
 if info.file_size>250_000_000:raise ValueError('Table exceeds preparation size limit')
 required={'REF_DATE','GEO','Statistic','Before-tax household income quintile','Household expenditures, summary-level categories','UOM','SCALAR_FACTOR','VECTOR','COORDINATE','VALUE','STATUS'}
 with z.open(info) as f:
  reader=csv.DictReader(io.TextIOWrapper(f,encoding='utf-8-sig'))
  if not required.issubset(set(reader.fieldnames or [])):raise ValueError('Official column schema changed; review importer')
  records=[r for r in reader if r['Statistic']=='Average expenditure per household' and r['Household expenditures, summary-level categories'] in LABELS]
 reference=max(r['REF_DATE'] for r in records);records=[r for r in records if r['REF_DATE']==reference]
 series=[];seen=set()
 for r in records:
  if r['UOM']!='Dollars' or r['SCALAR_FACTOR']!='units':raise ValueError('Unexpected source unit')
  geo=r['GEO'];quintile=r['Before-tax household income quintile'];key=(geo,quintile,r['VECTOR'])
  if key in seen:raise ValueError('Ambiguous source series')
  seen.add(key);status=r['STATUS'].strip();raw=r['VALUE'].strip();usable=bool(re.fullmatch(r'\d+(?:\.\d{1,2})?',raw)) and status in ('','E','p','r')
  if usable:float(raw)
  series.append({'source_table':'11-10-0223-01','source_url':TABLE_URL,'reference_year':int(reference),'cohort_label':geo+' · '+quintile,'dimensions':{'GEO':geo,'Before-tax household income quintile':quintile},'expenditure_label':r['Household expenditures, summary-level categories'],'value_annual':raw if usable else None,'currency':'CAD','unit':'CAD/year','status':status,'suppressed':not usable,'vector':r['VECTOR'],'coordinate':r['COORDINATE']})
 payload={'source':'Statistics Canada, Table 11-10-0223-01','source_url':TABLE_URL,'download_url':URL,'archive_sha256':hashlib.sha256(data).hexdigest(),'retrieved_at':datetime.now(timezone.utc).isoformat(),'reference_year':int(reference),'statistic':'Average expenditure per household','basis':'Annual nominal CAD; monthly presentation divides by 12. No inflation adjustment.','mapping_note':'No categories mapped automatically. Broad food, shelter and transportation totals excluded to avoid overlapping or incompatible cash-flow concepts.','records':series}
 Path(args.output).write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'output':args.output,'year':reference,'records':len(series),'cohorts':len(set(r['cohort_label'] for r in series)),'sha256':payload['archive_sha256']}))
if __name__=='__main__':main()
