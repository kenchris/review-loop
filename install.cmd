@echo off
rem Windows entry point of install.sh: finds the bash of Git for Windows (not WSL's) and runs the installer with it.
rem   .\install.cmd --for all --add-to-path
rem In PowerShell, `./install.sh` would open the file in an editor, and `bash` may be WSL's, which installs into the Linux home.
setlocal EnableExtensions
set "GITBASH="
for /f "delims=" %%G in ('where git 2^>nul') do (
  if not defined GITBASH if exist "%%~dpG..\bin\bash.exe" set "GITBASH=%%~dpG..\bin\bash.exe"
  if not defined GITBASH if exist "%%~dpG..\..\bin\bash.exe" set "GITBASH=%%~dpG..\..\bin\bash.exe"
)
if not defined GITBASH if exist "%ProgramFiles%\Git\bin\bash.exe" set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined GITBASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "GITBASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined GITBASH (
  echo install needs the bash of Git for Windows ^(not WSL's bash^). Install Git for Windows first. 1>&2
  exit /b 2
)
"%GITBASH%" "%~dp0install.sh" %*
exit /b %errorlevel%
