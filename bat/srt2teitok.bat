@echo off
:: %~dp0 = folder where this .bat file lives
:: "..\scripts\" moves up one folder and into "scripts"
set script=%~dp0..\scripts\srt2teitok.pl

:: Input is the file you drop
set input=%~1
set output=%~dpn1.xml

perl "%script%" --file "%input%" --output "%output%"
pause