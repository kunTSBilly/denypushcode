# GSA WiFi Check Automation

This repository currently contains documentation for a Windows GSA automation setup.

## Components

- `Check-GSA(V2).ps1` (attached externally)
  - Supports two modes: `Boot` and `Auto`.
  - Sets `GlobalSecureAccessEngineService` and `GlobalSecureAccessTunnelingService` to `Manual` startup.
  - In `Boot` mode:ss
    - writes registry value `HKCU:\Software\Microsoft\Global Secure Access Client\IsPrivateAccessDisabledByUser = 1`
    - stops the GSA services.
  - In `Auto` mode:
    - pings `10.1.254.254dsdd` five times.
    - if all pings succeed, treats the network as internal and disables GSA.
    - if all pings fail, treats the network as external and enables GSA.
    - if results are mixed, leaves GSA state unchanged.

- `GSA WiFi Check System (SYSTEM).xml` (attached externally)
  - Windows Scheduled Task registered under `SYSTEM`.
  - Triggers on:
    - logon
    - session lock / unlock
    - WLAN connect event `8001`
    - WLAN disconnect event `8003`
    - NetworkProfile connect event `10001`
    - NetworkProfile disconnect event `10003`
  - Executes:
    - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\SYS\Check-GSA(V2)_System_Check.ps1" -Mode Auto`
  - Settings:
    - runs as Local System
    - highest available privilege
    - allowed on battery
    - ignores new instances if already running
    - execution time limit 1 hour

## Notes

- The actual script and scheduled task XML are not included in this repository folder; they were provided as attachments.
- If you want, I can help create a repo version of the script and the XML task, or add a launcher batch file and installation instructions.
