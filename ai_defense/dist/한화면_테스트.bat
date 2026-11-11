@echo off
rem AI Defense - single monitor test mode (two windows side by side)
cd /d "%~dp0"
start "" "%~dp0AIDefense.exe" -- --single
