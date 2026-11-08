import {defineConfig} from 'vite';
export default defineConfig({base:'/',publicDir:false,build:{outDir:'.browser-dist',emptyOutDir:true,rollupOptions:{input:'tests/browser/index.html'}}});
