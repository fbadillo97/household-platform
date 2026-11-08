// Every protected response belongs to one session generation. Sign-out/revocation invalidates it.
export class SessionFence{
 epoch=0;
 invalidate(){this.epoch++;}
 async run(task){const epoch=this.epoch;try{const result=await task();if(epoch!==this.epoch)throw Error('Stale session');return result;}catch(error){if(epoch!==this.epoch)throw Error('Stale session');throw error;}}
}
