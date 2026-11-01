/* Fixed identity-only registration. No input script, purchase, placement, or retry. */
#include "probe-common.h"
#include "session-config.h"
#include "boundary-pins.h"
#include "excluded-ranges.h"
#include "runtime-pins.h"
#include "fragment.h"
#include "idle-guard.h"
static BOOL freshThreadOwnerChain(unsigned char*base){
 unsigned char*klass=*(unsigned char**)(base+0x64c60f8UL);if(!klass)return FALSE;
 unsigned char*loop=*(unsigned char**)(klass+0x20);if((ULONG_PTR)loop!=PIN_LOOP)return FALSE;
 if(*(int*)(loop+0x10)!=EXPECTED_MANAGED_ID)return FALSE;
 unsigned char*context=*(unsigned char**)(loop+0x20);if((ULONG_PTR)context!=PIN_CONTEXT)return FALSE;
 if(*(ULONG_PTR*)context!=PIN_CONTEXTCLASS||*(int*)(context+0x28)!=EXPECTED_MANAGED_ID)return FALSE;
 if(*(ULONG_PTR*)(base+0x6535aa0UL)!=PIN_CONTEXTCLASS)return FALSE;
 klass=*(unsigned char**)(base+0x6535a88UL);if(!klass)return FALSE;
 unsigned char*fields=*(unsigned char**)(klass+0x20);if(!fields)return FALSE;
 unsigned char*thread=*(unsigned char**)fields;if((ULONG_PTR)thread!=PIN_THREAD)return FALSE;
 if(*(ULONG_PTR*)thread!=PIN_THREADCLASS||*(ULONG_PTR*)(base+0x656a308UL)!=PIN_THREADCLASS)return FALSE;
 unsigned char*internal=*(unsigned char**)(thread+0x10);if((ULONG_PTR)internal!=PIN_INTERNAL)return FALSE;
 if(*(ULONG_PTR*)internal!=PIN_INTERNALCLASS||*(int*)(internal+0xb8)!=EXPECTED_MANAGED_ID||*(ULONGLONG*)(internal+0x50)!=EXPECTED_TID)return FALSE;
 return TRUE;
}
static LONG handled;static volatile LONG armed=PROBE_ARMED;
typedef void*(*NewString)(const char*,int);typedef DWORD(*NewHandle)(void*,BOOLEAN);typedef void*(*GetTarget)(DWORD);typedef void(*FreeHandle)(DWORD);typedef void*(*Invoke)(void*,void*,void**,void**);
static BOOL pin(unsigned char*b,const ApiPin*p,void**out){void*f=(void*)GetProcAddress((HMODULE)b,p->name);if(f!=b+p->rva||!bytes(f,p->bytes))return FALSE;*out=f;return TRUE;}
static BOOL nameEqual(const char*a,const char*b){for(unsigned i=0;i<32;i++){if(a[i]!=b[i])return FALSE;if(!a[i])return TRUE;}return FALSE;}
static void* methodFor(void*manager,unsigned char*b){
 unsigned char*cls=*(unsigned char**)manager;WORD n=*(WORD*)(cls+0x66);if(!n||n>1000)return 0;void**arr=*(void***)(*(unsigned char**)(cls+0x50)+0x10);void*found=0;
 for(WORD i=0;i<n;i++){unsigned char*m=arr[i];if(*(void**)m!=b+TARGET_RVA)continue;
  if(found||!nameEqual(*(char**)(m+0x18),"DoString")||*(void**)(m+0x20)!=cls||m[0x52]!=1||(m[0x53]&3)||(*(WORD*)(m+0x4c)&0x10)||*(void**)(m+0x10)!=b+INVOKER_RVA)return 0;
  unsigned char*ret=*(unsigned char**)(m+0x28);unsigned char*param=**(unsigned char***)(m+0x30);
  if(ret[10]!=1||param[10]!=14||!bytes(b+TARGET_RVA,targetExpected)||!bytes(b+INVOKER_RVA,invokerExpected))return 0;found=m;
 }return (ULONG_PTR)found==EXPECTED_METHOD_INFO?found:0;
}
static BOOL root(unsigned char*b,void**manager,unsigned char**L){
#if MOCK_RUNTIME
 typedef void*(*Root)(void);Root r=(Root)GetProcAddress((HMODULE)b,"MockManager");if(!r)return FALSE;*manager=r();*L=*(unsigned char**)(*(unsigned char**)((unsigned char*)*manager+24)+16);return TRUE;
#else
 if((ULONG_PTR)b!=EXPECTED_MODULE_BASE||!freshThreadOwnerChain(b))return FALSE;void*fac=*(void**)(b+0x6575dc0);void*sf=fac?*(void**)((unsigned char*)fac+32):0;*manager=sf?*(void**)((unsigned char*)sf+40):0;
 if(!*manager||(ULONG_PTR)*manager!=EXPECTED_LUA_MANAGER||*(ULONG_PTR*)*manager!=EXPECTED_MANAGER_CLASS)return FALSE;
 void*env=*(void**)((unsigned char*)*manager+24);*L=env?*(unsigned char**)((unsigned char*)env+16):0;return *L&&(ULONG_PTR)*L==EXPECTED_RAWL&&(*L)[9]==6;
#endif
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID unused){
 (void)unused;if(reason==DLL_PROCESS_ATTACH){WCHAR path[1100];DWORD len=GetModuleFileNameW(module,path,1090);
 if(len&&len<1090){path[len++]=L'.';path[len++]=L'c';path[len++]=L'f';path[len++]=L'g';path[len]=0;
 HANDLE f=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,0,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
 if(f!=INVALID_HANDLE_VALUE){DWORD n=0;loaded=ReadFile(f,&cfg,sizeof(cfg),&n,0)&&n==sizeof(cfg)&&cfg.n[0]==0x41544c4153434f4eULL&&cfg.n[1]==1&&(cfg.n[18]==3||cfg.n[18]==4||cfg.n[18]==5||cfg.n[18]==6||cfg.n[18]==7||cfg.n[18]==8||cfg.n[18]==9||cfg.n[18]==10||cfg.n[18]==11||cfg.n[18]==12||cfg.n[18]==13||cfg.n[18]==14||cfg.n[18]==15||cfg.n[18]==16||cfg.n[18]==17||cfg.n[18]==18||cfg.n[18]==19||cfg.n[18]==20||cfg.n[18]==21||cfg.n[18]==22||cfg.n[18]==23||cfg.n[18]==24||cfg.n[18]==25||cfg.n[18]==26||cfg.n[18]==27)&&cfg.message[127]==0&&cfg.output[1023]==0;CloseHandle(f);}}}return TRUE;}
__declspec(dllexport) LRESULT CALLBACK AtlasIdentityProbe(int code,WPARAM wp,LPARAM lp){if(loaded&&code>=0&&lp&&GetCurrentProcessId()==EXPECTED_PID&&GetCurrentThreadId()==EXPECTED_TID){MSG*m=(MSG*)lp;UINT msg=RegisterWindowMessageW(PROBE_MESSAGE);
 if(armed&&m->hwnd==(HWND)(ULONG_PTR)EXPECTED_HWND&&m->message==msg&&m->wParam==PROBE_NONCE_A&&m->lParam==PROBE_NONCE_B&&InterlockedCompareExchange(&handled,1,0)==0){
  BOOL pins=FALSE,first=FALSE,last=FALSE,matched=FALSE,called=FALSE,exception=FALSE,fault=FALSE,post=FALSE;char managedError[513]={0};DWORD hs=0,hm=0,freed=0,n1=0,n2=0;void*f[5]={0};unsigned char*b=(unsigned char*)GetModuleHandleW(RUNTIME_MODULE),*xl=(unsigned char*)GetModuleHandleW(L"xlua.dll"),*L=0;void*manager=0,*method=0;
  __try{if(imageSize(b)&&root(b,&manager,&L)){
#if !MOCK_RUNTIME
   if(!imageSize(xl)||!bytes(xl+0x2fb6,xluaEntry))__leave;
#endif
   pins=TRUE;for(unsigned i=0;i<5;i++)if(!pin(b,&apiPins[i],&f[i]))pins=FALSE;
   method=methodFor(manager,b);if(!pins||!method)__leave;
   first=idleGuard(L,
#if MOCK_RUNTIME
   0,
#else
   b,
#endif
   xl,&n1);if(!first)__leave;
   hm=((NewHandle)f[1])(manager,FALSE);if(!hm)__leave;
   void*s=((NewString)f[0])(fixedFragment,(int)(sizeof(fixedFragment)-1));if(!s)__leave;
   hs=((NewHandle)f[1])(s,FALSE);if(!hs)__leave;void*t=((GetTarget)f[2])(hs);
   if(t!=s||*(int*)((unsigned char*)t+16)!=(sizeof(fixedFragment)-1))__leave;
   matched=TRUE;WCHAR*ch=(WCHAR*)((unsigned char*)t+20);for(unsigned i=0;i<sizeof(fixedFragment)-1;i++)if(ch[i]!=(WCHAR)(unsigned char)fixedFragment[i])matched=FALSE;if(!matched)__leave;
   void*again=0;unsigned char*againL=0;if(!root(b,&again,&againL)||again!=manager||againL!=L||((GetTarget)f[2])(hm)!=manager||methodFor(manager,b)!=method)__leave;
   last=idleGuard(L,
#if MOCK_RUNTIME
   0,
#else
   b,
#endif
   xl,&n2);if(!last)__leave;
   void*args[1]={t};void*exc=0;called=TRUE;((Invoke)f[4])(method,manager,args,&exc);exception=exc!=0;if(exc){__try{unsigned char*message=*(unsigned char**)((unsigned char*)exc+24);if(message){int length=*(int*)(message+16);if(length>0&&length<=4096){if(length>512)length=512;WCHAR*text=(WCHAR*)(message+20);for(int k=0;k<length;k++){unsigned ch=text[k];managedError[k]=(ch>=32&&ch<127&&ch!=34&&ch!=92)?(char)ch:' ';}}}}__except(EXCEPTION_EXECUTE_HANDLER){managedError[0]=0;}}
   Tuple a=tuple(L),z=tuple(L);post=same(&a,&z)&&a.status==0&&!a.cframe&&a.base==a.stack+16&&a.top==a.base&&a.current==a.L&&a.vm==-2;
  }}__except(EXCEPTION_EXECUTE_HANDLER){fault=TRUE;}
  if(hs&&f[3]){DWORD h=hs;hs=0;__try{((FreeHandle)f[3])(h);freed++;}__except(EXCEPTION_EXECUTE_HANDLER){fault=TRUE;}}
  if(hm&&f[3]){DWORD h=hm;hm=0;__try{((FreeHandle)f[3])(h);freed++;}__except(EXCEPTION_EXECUTE_HANDLER){fault=TRUE;}}
  add("{");boolean("\"apiPinsValid\":",pins);boolean(",\"exactMethodVerified\":",method!=0);boolean(",\"initialIdleStackGuard\":",first);boolean(",\"fixedManagedStringMatched\":",matched);boolean(",\"immediateIdleStackGuard\":",last);boolean(",\"runtimeInvokeCalled\":",called);boolean(",\"managedException\":",exception);boolean(",\"postInvokeIdle\":",post);boolean(",\"nativeFault\":",fault);add(",\"managedError\":\"");add(managedError);add("\"");add(",\"handlesFreed\":");num(freed);add(",\"initialFrames\":");num(n1);add(",\"immediateFrames\":");num(n2);add(",\"fragmentSHA256\":\"");add(FRAGMENT_SHA256);add("\"");
#if MOCK_RUNTIME
 add(",\"mockOnly\":true");
#else
 add(",\"mockOnly\":false");
#endif
 add(",\"registrationConfirmed\":false,\"scope\":\"authenticated build-workflow registration; no purchase or placement dispatched\"}\n");save(PROBE_OUTPUT);
 }}return CallNextHookEx(0,code,wp,lp);}
