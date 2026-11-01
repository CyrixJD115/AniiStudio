#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
static char textbuf[16384];static DWORD textlen;
static void add(const char*s){while(*s&&textlen<sizeof(textbuf)-1)textbuf[textlen++]=*s++;}
static void num(ULONGLONG x){char b[24];unsigned n=0;do{b[n++]=(char)('0'+x%10);x/=10;}while(x);while(n&&textlen<sizeof(textbuf)-1)textbuf[textlen++]=b[--n];}
static ULONGLONG parse(const WCHAR*s){ULONGLONG n=0;while(*s>='0'&&*s<='9')n=n*10+*s++-'0';return n;}
static BOOL save(const WCHAR*path){HANDLE f=CreateFileW(path,GENERIC_WRITE,0,0,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);if(f==INVALID_HANDLE_VALUE)return FALSE;DWORD n=0;BOOL ok=WriteFile(f,textbuf,textlen,&n,0)&&n==textlen;CloseHandle(f);return ok;}
