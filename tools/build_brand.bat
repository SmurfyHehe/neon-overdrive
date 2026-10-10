@echo off
rem Rebuilds every brand file (icon, boot splash, Steam art) from tools/build_brand.py.
setlocal
cd /d "%~dp0.."
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Documents\Godot_v4.7.2-stable_win64_console.exe
python tools\build_brand.py || exit /b 1
"%GODOT%" --headless --path . -s tools/brand_raster.gd || exit /b 1
python tools\build_brand.py pack || exit /b 1
