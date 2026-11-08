import {defineConfig} from 'vite';
export default defineConfig({base:process.env.VITE_APP_BASE||'/',build:{sourcemap:false}});
