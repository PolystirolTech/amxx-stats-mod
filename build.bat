@echo off
echo Building AMXX Stats Mod...
echo.

set "AMXXPC="

REM Check environment variable first
if defined AMXXPC_PATH (
	set "AMXXPC=%AMXXPC_PATH%"
	echo Using compiler from AMXXPC_PATH: %AMXXPC%
	goto :compile
)

REM Check if amxxpc is in PATH
where amxxpc >nul 2>&1
if %ERRORLEVEL% EQU 0 (
	set "AMXXPC=amxxpc"
	echo Using compiler from PATH
	goto :compile
)

REM Check standard installation paths
if exist "C:\Program Files\AMX Mod X\scripting\amxxpc.exe" (
	set "AMXXPC=C:\Program Files\AMX Mod X\scripting\amxxpc.exe"
	echo Using compiler from: %AMXXPC%
	goto :compile
)

if exist "C:\Program Files (x86)\AMX Mod X\scripting\amxxpc.exe" (
	set "AMXXPC=C:\Program Files (x86)\AMX Mod X\scripting\amxxpc.exe"
	echo Using compiler from: %AMXXPC%
	goto :compile
)

REM Check common server locations
if exist "..\addons\amxmodx\scripting\amxxpc.exe" (
	set "AMXXPC=..\addons\amxmodx\scripting\amxxpc.exe"
	echo Using compiler from: %AMXXPC%
	goto :compile
)

if exist "addons\amxmodx\scripting\amxxpc.exe" (
	set "AMXXPC=addons\amxmodx\scripting\amxxpc.exe"
	echo Using compiler from: %AMXXPC%
	goto :compile
)

REM Compiler not found
echo.
echo ERROR: AMXX compiler not found!
echo.
echo Please do one of the following:
echo   1. Add amxxpc.exe to your PATH
echo   2. Set AMXXPC_PATH environment variable to full path of amxxpc.exe
echo   3. Install AMX Mod X SDK in default location
echo   4. Place amxxpc.exe in project root directory
echo.
echo Example: set AMXXPC_PATH=C:\path\to\amxxpc.exe
echo.
pause
exit /b 1

:compile
if not exist "compiled" mkdir compiled

echo.
echo Compiling stats_mod.sma...
"%AMXXPC%" -iinclude src/stats_mod.sma -ocompiled/stats_mod.amxx

if %ERRORLEVEL% EQU 0 (
	echo.
	echo Build successful!
	echo Output: compiled/stats_mod.amxx
) else (
	echo.
	echo Build failed! Check errors above.
	exit /b 1
)

pause

