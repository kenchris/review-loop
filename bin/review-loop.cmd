@echo off
rem Runs the review-loop launcher that sits next to this file, with the bash of Git for Windows.
rem `bash` on the PATH may be WSL's, which cannot open a Windows path, so Git's bash is looked up through git itself.
setlocal EnableExtensions
set "GITBASH="
for /f "delims=" %%G in ('where git 2^>nul') do (
  if not defined GITBASH if exist "%%~dpG..\bin\bash.exe" set "GITBASH=%%~dpG..\bin\bash.exe"
  if not defined GITBASH if exist "%%~dpG..\..\bin\bash.exe" set "GITBASH=%%~dpG..\..\bin\bash.exe"
)
if not defined GITBASH if exist "%ProgramFiles%\Git\bin\bash.exe" set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined GITBASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "GITBASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined GITBASH (
  echo review-loop needs the bash of Git for Windows ^(not WSL's bash^). Install Git for Windows, or run review-loop from Git Bash. 1>&2
  exit /b 2
)
"%GITBASH%" "%~dp0review-loop" %*
exit /b %errorlevel%
