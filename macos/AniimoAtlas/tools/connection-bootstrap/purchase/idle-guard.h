void* memset(void*p,int c,SIZE_T n){volatile unsigned char*q=(volatile unsigned char*)p;while(n--)*q++=(unsigned char)c;return p;}

typedef USHORT (WINAPI *Capture)(ULONG,ULONG,PVOID*,PULONG);
typedef struct{ULONG_PTR L,g,base,top,stack,cframe,current;LONG vm;BYTE status;}Tuple;
static BOOL bytes(unsigned char*p,const unsigned char*q){for(unsigned i=0;i<32;i++)if(p[i]!=q[i])return FALSE;return TRUE;}
static DWORD imageSize(unsigned char*b){if(!b||b[0]!='M'||b[1]!='Z')return 0;DWORD p=*(DWORD*)(b+60);if(p>65536||*(DWORD*)(b+p)!=0x4550||*(WORD*)(b+p+4)!=0x8664)return 0;return *(DWORD*)(b+p+24+56);}
static Tuple tuple(unsigned char*l){Tuple t;t.L=(ULONG_PTR)l;t.g=*(ULONG_PTR*)(l+16);t.base=*(ULONG_PTR*)(l+32);t.top=*(ULONG_PTR*)(l+40);t.stack=*(ULONG_PTR*)(l+56);t.cframe=*(ULONG_PTR*)(l+80);t.status=l[11];t.current=*(ULONG_PTR*)(t.g+368);t.vm=*(LONG*)(t.g+184);return t;}
static BOOL same(Tuple*a,Tuple*b){return a->L==b->L&&a->g==b->g&&a->base==b->base&&a->top==b->top&&a->stack==b->stack&&a->cframe==b->cframe&&a->current==b->current&&a->status==b->status&&a->vm==b->vm;}
static void boolean(const char*k,BOOL v){add(k);add(v?"true":"false");}
static void moduleName(WCHAR*p){DWORD i=0,last=0;while(p[i]){if(p[i]=='\\'||p[i]=='/')last=i+1;i++;}add("\"");for(i=last;p[i];i++){char c=(char)p[i];if(c=='"'||c=='\\'||p[i]>126||p[i]<32)c='_';char s[2]={c,0};add(s);}add("\"");}

static BOOL idleGuard(unsigned char*l,unsigned char*game,unsigned char*xl,DWORD*count){
 unsigned char*nt=(unsigned char*)GetModuleHandleW(L"ntdll.dll");if(!imageSize(nt))return FALSE;
 Capture c=(Capture)GetProcAddress((HMODULE)nt,"RtlCaptureStackBackTrace");
 if((void*)c!=nt+CAPTURE_RVA||!bytes((unsigned char*)c,captureExpected)||!bytes(nt+THREAD_ROOT_RVA,threadRootExpected))return FALSE;
 Tuple a=tuple(l),z;void*frames[64]={0};USHORT n=c(0,64,frames,0);z=tuple(l);*count=n;
 if(!same(&a,&z)||a.status||a.cframe||a.base!=a.stack+16||a.top!=a.base||a.current!=a.L||a.vm!=-2||n<4||n==64)return FALSE;
 BOOL terminal=FALSE;for(USHORT i=0;i<n;i++){
 HMODULE mod=0;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,(LPCWSTR)frames[i],&mod))return FALSE;
 DWORD size=imageSize((unsigned char*)mod);ULONG_PTR off=(ULONG_PTR)frames[i]-(ULONG_PTR)mod;if(!size||off>=size)return FALSE;
 if(mod==(HMODULE)xl)return FALSE;
 if(mod==(HMODULE)game)for(unsigned j=0;j<sizeof(excludedRanges)/sizeof(excludedRanges[0]);j++)if(off>=excludedRanges[j][0]&&off<=excludedRanges[j][1])return FALSE;
 if(i==n-1)terminal=mod==(HMODULE)nt&&off>=THREAD_ROOT_RVA&&off<THREAD_ROOT_END;
 }return terminal;
}
