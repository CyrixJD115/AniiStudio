from pathlib import Path
import subprocess,sys
r=Path.cwd();o=r/'tools/connection-bootstrap';llvm=Path('/opt/homebrew/opt/llvm/bin');wine=Path('/Users/kevinhowe/Library/Application Support/com.gamemac.www/wine-engine/containers/wine_installations/10000033');libs=[]
imports={'kernel32':['ExitProcess','GetCommandLineW','CreateFileW','WriteFile','CloseHandle','GetCurrentProcessId','GetCurrentThreadId','GetModuleHandleW','GetModuleFileNameW','ReadFile','GetTickCount64','Sleep','LoadLibraryW','GetProcAddress','FreeLibrary','GetLastError','CreateToolhelp32Snapshot','Process32FirstW','Process32NextW'],'shell32':['CommandLineToArgvW'],'user32':['DefWindowProcW','RegisterClassW','CreateWindowExW','PeekMessageW','TranslateMessage','DispatchMessageW','DestroyWindow','GetWindowThreadProcessId','RegisterWindowMessageW','SetWindowsHookExW','PostMessageW','UnhookWindowsHookEx','CallNextHookEx','EnumWindows','GetClassNameW','GetWindowTextW','IsWindowVisible','GetProcessWindowStation','GetThreadDesktop','GetUserObjectInformationW','EnumDesktopsW','OpenDesktopW','EnumDesktopWindows','CloseDesktop']}
for name,funcs in imports.items():
 d=o/(name+'.def');d.write_text('LIBRARY '+name+'.dll\nEXPORTS\n'+'\n'.join(funcs)+'\n');l=o/(name+'.lib');subprocess.run([str(llvm/'llvm-dlltool'),'-m','i386:x86-64','-d',str(d),'-l',str(l)],check=True);libs.append(str(l))
for name in sys.argv[1:]:
 obj=o/(name+'.obj');subprocess.run([str(llvm/'clang'),'--target=x86_64-windows-msvc','-O2','-ffreestanding','-fno-stack-protector','-isystem',str(wine/'include/wine/windows'),'-isystem',str(wine/'include/wine/msvcrt'),'-c',str(o/(name+'.c')),'-o',str(obj)],check=True)
 dll=name=='probe-dll';exe=o/(name+('.dll'if dll else'.exe'));args=['/dll','/entry:DllMain']if dll else['/entry:mainCRTStartup','/subsystem:console'];subprocess.run(['/opt/homebrew/opt/lld/bin/lld-link',*args,'/nodefaultlib','/out:'+str(exe),str(obj),*libs],check=True)
 print(exe)
