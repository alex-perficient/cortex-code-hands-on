# run_extract.ps1 - Wrapper script for Windows Task Scheduler
# Runs extract_data.py with UTF-8 encoding to avoid emoji issues on Windows

$env:PYTHONIOENCODING = 'utf-8'
Set-Location "C:\Users\alejandro.pedrero\cortex-code-hands-on\urban-biker-lakehouse"
& "C:\Program Files\Python311\python.exe" scripts\extract_data.py
