@echo off
rem Fast dev/test server: builds + hosts the tiny virgo_minitest map instead of
rem the full Southern Cross station, so startup is a few seconds instead of ~70s.
rem Use for iterating on code that doesn't need the real station.
call "%~dp0\..\tools\build\build.bat" --wait-on-error server -DUSE_MAP_MINITEST %*
