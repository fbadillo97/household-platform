import test from 'node:test';import assert from 'node:assert/strict';import {authSessionIdentity} from '../src/lifecycle.js';
const session=(sub,sid,version=1)=>({user:{id:sub},access_token:'header.'+Buffer.from(JSON.stringify({sub,session_id:sid,version})).toString('base64url')+'.signature'});
test('session lifecycle identity survives token rotation and distinguishes new sessions and users',()=>{
 assert.equal(authSessionIdentity(session('user','first',1)),authSessionIdentity(session('user','first',2)));assert.notEqual(authSessionIdentity(session('user','first')),authSessionIdentity(session('user','second')));assert.notEqual(authSessionIdentity(session('user','first')),authSessionIdentity(session('other','first')));
 for(const s of [null,{},session('user',null),{user:{id:'other'},access_token:session('user','first').access_token},{user:{id:'user'},access_token:'malformed'}])assert.equal(authSessionIdentity(s),null);
});
