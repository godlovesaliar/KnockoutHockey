@echo off
rem Chatterbox TTS server for SillyTavern: http://127.0.0.1:8004/v1/audio/speech
rem Close the Studio and voicegen first - only one of them should run at a time.
cd /d "%~dp0"
venv\Scripts\python.exe studio\tts_server.py %*
pause
