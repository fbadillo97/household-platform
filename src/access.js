export function phaseForAccess(state){
 if(state.status!=='approved')return state.status;
 return state.passkey_verified===true?'approved':'passkey_required';
}
