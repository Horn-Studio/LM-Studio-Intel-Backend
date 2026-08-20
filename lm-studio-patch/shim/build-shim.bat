@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cl /nologo /O2 /EHsc /Fe:C:\Users\Horn.Studio\Music\dsh\llama-server-shim.exe C:\Users\Horn.Studio\Music\dsh\shim.c
