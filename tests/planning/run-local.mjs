// Isolated PostgreSQL tests. Optional local-only PGlite installation, never an app dependency.
import {readFile,readdir} from 'node:fs/promises';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';
const modulePath=process.env.PLANNING_PGLITE_MODULE;
const {PGlite}=await import(modulePath?pathToFileURL(resolve(modulePath)).href:'@electric-sql/pglite'),db=new PGlite();
try{await db.exec(await readFile('tests/planning/bootstrap.sql','utf8'));for(const file of (await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort()){try{await db.exec(await readFile('supabase/migrations/'+file,'utf8'));}catch(e){console.error('Migration',file,e.message,e.detail,e.where);throw e;}}
 console.log('Repository migrations compile');
 for(const file of process.argv.slice(2)){try{const results=await db.exec(await readFile(file,'utf8'));console.log(file,JSON.stringify(results.filter(r=>r.rows?.length).map(r=>r.rows)));}catch(e){console.error('Fixture',file,e.message,e.detail,e.where,e.position);throw e;}}
}catch(e){console.error(JSON.stringify({error:e.message,detail:e.detail,where:e.where,position:e.position}));process.exitCode=1;}finally{await db.close();}
