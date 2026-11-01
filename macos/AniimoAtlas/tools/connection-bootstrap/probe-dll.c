/* Session-bound lifecycle only. No Lua execution, transactions or game-data setters. */
#include "probe-common.h"
typedef struct { ULONGLONG n[19]; WCHAR message[128]; WCHAR output[1024]; } Config;
static Config cfg;static BOOL loaded;static LONG handled;
static const unsigned char authloadExpected[32]={72,137,92,36,16,72,137,76,36,8,86,87,65,86,72,131,236,48,72,139,241,51,210,185,57,42,0,0,232,143,92,94};
static const unsigned char startExpected[32]={72,137,92,36,16,72,137,76,36,8,86,87,65,86,72,131,236,48,72,139,249,51,210,185,56,42,0,0,232,207,109,94};
static const unsigned char stopExpected[32]={72,139,196,72,137,88,16,72,137,72,8,86,87,65,86,72,129,236,128,0,0,0,72,139,241,69,51,246,76,137,112,24};
static BOOL currentOwnerChain(unsigned char*base){
 unsigned char*klass=*(unsigned char**)(base+0x64c60f8UL);if(!klass)return FALSE;
 unsigned char*loop=*(unsigned char**)(klass+0x20);if((ULONG_PTR)loop!=cfg.n[9])return FALSE;
 if(*(int*)(loop+0x10)!=cfg.n[8])return FALSE;
 unsigned char*context=*(unsigned char**)(loop+0x20);if((ULONG_PTR)context!=cfg.n[10])return FALSE;
 if(*(ULONG_PTR*)context!=cfg.n[11]||*(int*)(context+0x28)!=cfg.n[8])return FALSE;
 if(*(ULONG_PTR*)(base+0x6535aa0UL)!=cfg.n[11])return FALSE;
 klass=*(unsigned char**)(base+0x6535a88UL);if(!klass)return FALSE;
 unsigned char*fields=*(unsigned char**)(klass+0x20);if(!fields)return FALSE;
 unsigned char*thread=*(unsigned char**)fields;if((ULONG_PTR)thread!=cfg.n[12])return FALSE;
 if(*(ULONG_PTR*)thread!=cfg.n[13]||*(ULONG_PTR*)(base+0x656a308UL)!=cfg.n[13])return FALSE;
 unsigned char*internal=*(unsigned char**)(thread+0x10);if((ULONG_PTR)internal!=cfg.n[14])return FALSE;
 if(*(ULONG_PTR*)internal!=cfg.n[15]||*(int*)(internal+0xb8)!=cfg.n[8]||*(ULONGLONG*)(internal+0x50)!=cfg.n[3])return FALSE;
 klass=*(unsigned char**)(base+0x6575dc0UL);if(!klass)return FALSE;fields=*(unsigned char**)(klass+0x20);if(!fields)return FALSE;
 unsigned char*manager=*(unsigned char**)(fields+0x38);return (ULONG_PTR)manager==cfg.n[6]&&*(ULONG_PTR*)manager==cfg.n[7];
}

BOOL WINAPI DllMain(HINSTANCE m,DWORD reason,LPVOID unused){
 (void)unused;if(reason==DLL_PROCESS_ATTACH){WCHAR path[1100];DWORD len=GetModuleFileNameW(m,path,1090);
 if(len&&len<1090){path[len++]=L'.';path[len++]=L'c';path[len++]=L'f';path[len++]=L'g';path[len]=0;
 HANDLE f=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,0,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
 if(f!=INVALID_HANDLE_VALUE){DWORD n=0;loaded=ReadFile(f,&cfg,sizeof(cfg),&n,0)&&n==sizeof(cfg)&&cfg.n[0]==0x41544c4153434f4eULL&&cfg.n[1]==1&&cfg.n[18]<=2&&cfg.message[127]==0&&cfg.output[1023]==0;CloseHandle(f);}}}return TRUE;}
__declspec(dllexport) LRESULT CALLBACK AtlasIdentityProbe(int code,WPARAM wp,LPARAM lp){
 if(loaded&&code>=0&&lp&&GetCurrentProcessId()==cfg.n[2]&&GetCurrentThreadId()==cfg.n[3]){
 MSG*m=(MSG*)lp;UINT message=RegisterWindowMessageW(cfg.message);
 if(m->hwnd==(HWND)(ULONG_PTR)cfg.n[4]&&m->message==message&&m->wParam==(WPARAM)cfg.n[16]&&m->lParam==(LPARAM)cfg.n[17]&&InterlockedCompareExchange(&handled,1,0)==0){
 unsigned char*base=(unsigned char*)GetModuleHandleW(L"GameAssembly.dll");BOOL pinned=FALSE,chain=FALSE,called=FALSE,result=FALSE,before=FALSE,after=FALSE;DWORD port=0;
 const unsigned char*expected=cfg.n[18]==0?authloadExpected:cfg.n[18]==1?startExpected:stopExpected;
 ULONG_PTR rva=cfg.n[18]==0?0x16b9e10UL:cfg.n[18]==1?0x16b8cd0UL:0x16b90c0UL;
 if(base&&(ULONG_PTR)base==cfg.n[5]&&base[0]=='M'&&base[1]=='Z'){
 DWORD pe=*(DWORD*)(base+60);if(pe<0x10000&&*(DWORD*)(base+pe)==0x4550&&*(WORD*)(base+pe+4)==0x8664){pinned=TRUE;for(unsigned i=0;i<32;i++)if(base[rva+i]!=expected[i])pinned=FALSE;}}
 if(pinned)chain=currentOwnerChain(base);
 if(chain){unsigned char*self=(unsigned char*)(ULONG_PTR)cfg.n[6];before=self[0x48]!=0;
 unsigned char*key=*(unsigned char**)(self+0x40);BOOL auth=key&&*(int*)(key+0x10)==64;
 if(cfg.n[18]==0&&!before){typedef void(*Load)(void*,const void*);((Load)(base+rva))(self,0);called=TRUE;result=TRUE;}
 if(cfg.n[18]==1&&!before&&auth){typedef unsigned char(*Start)(void*,const void*);result=((Start)(base+rva))(self,0)!=0;called=TRUE;}
 if(cfg.n[18]==2&&before){typedef void(*Stop)(void*,const void*);((Stop)(base+rva))(self,0);called=TRUE;result=TRUE;}
 after=self[0x48]!=0;port=*(DWORD*)(self+0x38);}
 add("{\"methodBytesPinned\":");add(pinned?"true":"false");add(",\"freshOwnerChainPinned\":");add(chain?"true":"false");add(",\"called\":");add(called?"true":"false");add(",\"result\":");add(result?"true":"false");add(",\"runningBefore\":");add(before?"true":"false");add(",\"runningAfter\":");add(after?"true":"false");add(",\"activePort\":");num(port);add("}\n");save(cfg.output);
 }}return CallNextHookEx(0,code,wp,lp);}
