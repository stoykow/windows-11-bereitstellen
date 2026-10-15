@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Run during the specialize pass as SYSTEM, or manually from an elevated CMD.
rem All operations can be repeated. Existing services are not stopped here.
rem This file uses UTF-8 without BOM; its output is ASCII for CMD compatibility.
rem Policy references:
rem https://learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy#disableadvertisingid
rem https://learn.microsoft.com/windows/client-management/mdm/policy-csp-system#allowtelemetry
rem https://learn.microsoft.com/windows/client-management/mdm/policy-csp-experience
rem https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services#16-onedrive
rem https://learn.microsoft.com/deployedge/microsoft-edge-policies/BackgroundModeEnabled
rem https://learn.microsoft.com/deployedge/microsoft-edge-browser-policies/experimentationandconfigurationservicecontrol

set "NativeSystem=%SystemRoot%\System32"
if exist "%SystemRoot%\Sysnative\reg.exe" set "NativeSystem=%SystemRoot%\Sysnative"
set "RegExe=%NativeSystem%\reg.exe"
set "ScExe=%NativeSystem%\sc.exe"

"%NativeSystem%\fltmc.exe" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Run this script as Administrator or SYSTEM.
    exit /b 1
)

set "LogDir=%WINDIR%\Setup\Scripts"
set "LogFile=%LogDir%\Configure-Windows.log"
if not exist "%LogDir%" mkdir "%LogDir%" >nul 2>&1
if not exist "%LogDir%" (
    echo ERROR: Cannot create the log directory "%LogDir%".
    exit /b 1
)
>>"%LogFile%" echo [%date% %time%] Starting Configure-Windows.cmd
if errorlevel 1 (
    echo ERROR: Cannot write to "%LogFile%".
    exit /b 1
)

set "Failures=0"
set "EditionID="
set "BuildNumber="
set "BuildRevision="
set "DisplayVersion="
for /f "tokens=2,*" %%A in ('""%RegExe%" query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID /reg:64 2^>nul"') do if /i "%%A"=="REG_SZ" set "EditionID=%%B"
for /f "tokens=2,*" %%A in ('""%RegExe%" query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber /reg:64 2^>nul"') do if /i "%%A"=="REG_SZ" set "BuildNumber=%%B"
for /f "tokens=2,*" %%A in ('""%RegExe%" query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v UBR /reg:64 2^>nul"') do if /i "%%A"=="REG_DWORD" set "BuildRevision=%%B"
for /f "tokens=2,*" %%A in ('""%RegExe%" query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion /reg:64 2^>nul"') do if /i "%%A"=="REG_SZ" set "DisplayVersion=%%B"
if not defined EditionID (
    call :Error "Cannot read EditionID. Using conservative edition defaults."
    set "EditionID=Unknown"
)
if not defined BuildNumber (
    call :Error "Cannot read CurrentBuildNumber."
    set "BuildNumber=Unknown"
)
if not defined BuildRevision set "BuildRevision=Unknown"
if not defined DisplayVersion set "DisplayVersion=Unknown"
call :Log "Windows edition: %EditionID%; version: %DisplayVersion%; build: %BuildNumber%; UBR: %BuildRevision%."

rem Explicit allowlist: ProfessionalEducation is a Pro SKU, not Education.
rem Unknown and future edition IDs retain the conservative Pro defaults.
set "EnterpriseEducation=0"
for %%E in (Enterprise EnterpriseN EnterpriseS EnterpriseSN EnterpriseEval EnterpriseNEval EnterpriseSEval EnterpriseSNEval Education EducationN IoTEnterprise IoTEnterpriseS) do if /i "%EditionID%"=="%%E" set "EnterpriseEducation=1"
set "TelemetryLevel=1"
if "%EnterpriseEducation%"=="1" set "TelemetryLevel=0"
call :Log "AllowTelemetry target: %TelemetryLevel%. Policy support depends on the Windows edition."

rem A running service remains running until reboot. Missing services are skipped.
call :DisableService DiagTrack
call :DisableService dmwappushservice

rem Computer policies documented in the Privacy, Experience and System CSPs.
call :SetDword "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" DisabledByGroupPolicy 1
call :SetDword "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" DoNotShowFeedbackNotifications 1
call :SetDword "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" AllowTelemetry %TelemetryLevel%

rem Blocks OneDrive file storage and synchronization, including work/school use.
rem This is more than an autostart setting and does not uninstall OneDrive.
call :SetDword "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" DisableFileSyncNGSC 1

rem Consumer experience and Windows tips policies do not support Pro or Home.
if "%EnterpriseEducation%"=="1" (
    call :SetDword "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" DisableWindowsConsumerFeatures 1
    call :SetDword "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" DisableSoftLanding 1
) else (
    call :Log "SKIP: Consumer experience and Windows tips policies require Enterprise or Education."
)

call :SetDword "HKLM\SOFTWARE\Policies\Microsoft\Edge" BackgroundModeEnabled 0
rem ConfigurationsOnlyMode keeps compatibility fixes while excluding experiments.
rem Microsoft does not recommend RestrictedMode, which would be value 0.
call :SetDword "HKLM\SOFTWARE\Policies\Microsoft\Edge" ExperimentationAndConfigurationServiceControl 1

rem Home can ignore policies that Microsoft documents only for managed editions.
rem A successful registry write does not prove that a policy is supported/applied.
call :Log "Completed with %Failures% error(s). Review the entries above."
echo Log: "%LogFile%"
if not "%Failures%"=="0" exit /b 1
exit /b 0

:SetDword
"%RegExe%" add "%~1" /v "%~2" /t REG_DWORD /d "%~3" /f /reg:64 >>"%LogFile%" 2>&1
set "OperationResult=%errorlevel%"
if not "%OperationResult%"=="0" (
    call :Error "Cannot set %~1\%~2 to %~3, error %OperationResult%."
    exit /b 1
)
call :Log "OK: %~1\%~2 = %~3."
exit /b 0

:DisableService
"%ScExe%" query "%~1" >>"%LogFile%" 2>&1
set "OperationResult=%errorlevel%"
if "%OperationResult%"=="1060" (
    call :Log "SKIP: Service %~1 is not installed."
    exit /b 0
)
if not "%OperationResult%"=="0" (
    call :Error "Cannot query service %~1, error %OperationResult%."
    exit /b 1
)
"%ScExe%" config "%~1" start= disabled >>"%LogFile%" 2>&1
set "OperationResult=%errorlevel%"
if not "%OperationResult%"=="0" (
    call :Error "Cannot disable service %~1, error %OperationResult%."
    exit /b 1
)
call :Log "OK: Service %~1 startup is disabled. No stop was requested."
exit /b 0

:Error
set /a Failures+=1 >nul
call :Log "ERROR: %~1"
exit /b 0

:Log
echo [%date% %time%] %~1
>>"%LogFile%" echo [%date% %time%] %~1
exit /b 0
