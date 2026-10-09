@echo off
rem Benchmark the exported build (ISSUES B7, GitHub #19).
rem Export first (Project > Export > Windows Desktop -> build\BoostSimcade.exe).
rem The game drives itself for ~47 s with V-Sync off, then quits and appends
rem one line to build\benchmark-results.txt. Normal launches are unaffected.
if not exist "%~dp0build\BoostSimcade.exe" (
	echo build\BoostSimcade.exe not found - export the game first.
	pause
	exit /b 1
)
start "" /wait "%~dp0build\BoostSimcade.exe" -- --benchmark
echo.
echo Results so far (newest last):
type "%~dp0build\benchmark-results.txt"
echo.
pause
