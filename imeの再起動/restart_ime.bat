@echo off

set CMD=tasklist /fi "imagename eq ctfmon.exe"
for /f "usebackq tokens=2" %%a in (`%CMD%`) do @set pid=%%a
echo Current PID is %pid% 

taskkill /pid %pid% 
start ctfmon.exe

set CMD=tasklist /fi "imagename eq ctfmon.exe"
for /f "usebackq tokens=2" %%a in (`%CMD%`) do @set pid=%%a
echo New PID is %pid% 

pause
