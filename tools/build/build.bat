@echo off
setlocal
rem Build exactly this checkout; Bun's shared transpiler cache can cross worktrees.
for %%I in ("%~dp0..\..") do set "DQ_BUILD_ROOT=%%~fI"
set "BUN_RUNTIME_TRANSPILER_CACHE_PATH=0"
"%~dp0\..\bootstrap\javascript.bat" "%~dp0\build.ts" %*
