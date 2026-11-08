import {defineConfig} from 'vite';
export default defineConfig({base:process.env.VITE_APP_BASE||'/',build:{sourcemap:false,rollupOptions:{output:{manualChunks:{react:['react','react-dom','react-dom/client'],supabase:['@supabase/supabase-js'],csv:['papaparse']}}}}});
