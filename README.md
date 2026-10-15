# Windows 11 26H2: Installationsimage vorbereiten und bereitstellen

Diese Anleitung richtet sich vorrangig an **Windows 11 Pro 26H2 für x64 (amd64)**. Der Grundablauf mit DISM, einer Antwortdatei und Rufus lässt sich auch für ältere Windows-11-Versionen verwenden. Apps, Richtlinien und OOBE unterscheiden sich nach Version, Edition und Aktualisierungsstand.

**Dokumentationsstand: 15. Oktober 2026.** Die Befehle und XML wurden statisch geprüft. Das Konfigurationsskript wurde zusätzlich mit isolierten Testprogrammen geprüft. Eine vollständige Installation mit einer konkreten Windows-ISO steht noch aus.

## Geltungsbereich und ältere Versionen

| Zielversion | Verwendung dieser Anleitung |
| ----------- | -------------------------- |
| 26H2, x64 | Schwerpunkt der Anleitung. Die passende ISO und Edition verwenden, Antwortdatei und Installation prüfen. |
| 25H2, x64 | Gleicher Grundablauf. App-Liste aus dem eigenen Image ermitteln und Antwortdatei dagegen validieren. |
| 24H2, x64 | Grundablauf übertragbar. Neuere KI-Richtlinien benötigen den genannten Patchstand. Home/Pro erhalten seit dem 13. Oktober 2026 keine regulären Updates mehr. |
| 23H2, x64 | Versionsgerecht prüfen, moderne KI-Schritte überspringen. Home/Pro sind ohne reguläre Updates, Enterprise/Education werden bis zum 10. November 2026 unterstützt. |
| 22H2 und älter, x64 | Nur für gesondert geprüfte Altszenarien. Für neue produktive Installationen eine unterstützte Version wählen. |
| 26H1 und Arm64 | Eigener Geräte-/Architekturfall. Die amd64-Komponenten, Werkzeuge und Bootpfade nicht unverändert übernehmen. |

Microsoft dokumentiert den aktuellen Versions- und Supportstand unter [Windows 11 Release Information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information). Die Übertragbarkeit des Ablaufs ersetzt keinen Installationstest für jede Zielversion.

### Voraussetzungen

- Techniker-PC mit Windows, ausreichend freiem Speicher und **Windows PowerShell 5.1 als Administrator**.
- Unveränderte Original-ISO als Ausgangspunkt. Für jeden Versuch einen eigenen leeren Quellordner verwenden.
- Dieses Repository vollständig herunterladen oder klonen. Kopierbefehle für Repository-Dateien im Repository-Stamm ausführen.
- Die Beispiele für Produkt-Key und Antwortdatei beziehen sich auf **Pro**. Für andere Editionen die passende Edition und Antwortdatei verwenden.
- Anpassungen zunächst in einer VM testen, das fertige USB-Medium anschließend auf der vorgesehenen Hardware prüfen.

## 1. ISO herunterladen

Lade die Windows-11-ISO für die gewünschte Version und x64-Architektur von:
https://www.microsoft.com/de-de/software-download/windows11

Die Downloadseite bietet derzeit 26H2 an. Für eine ältere Zielversion eine unveränderte Original-ISO genau dieser Version verwenden. Die Anpassung einer 26H2-ISO erzeugt kein Installationsmedium für eine ältere Version.

---

## 2. ISO entpacken oder kopieren

Eine eingehängte ISO ist schreibgeschützt. Die Dateien müssen in einen beschreibbaren Ordner.

### Vorgehen

1. ISO per Rechtsklick bereitstellen
2. Kompletten Inhalt in einen Ordner kopieren, zum Beispiel: `C:\iso_source`

### Beispielstruktur

```
C:\iso_source
├── boot
├── efi
├── sources
├── support
└── setup.exe
```

---

## 3. Gewünschte Edition auswählen und als WIM exportieren

**Windows PowerShell 5.1 als Administrator öffnen.** Die Quelle kann `install.wim` oder `install.esd` enthalten. Zuerst prüfen:

```powershell
Get-ChildItem -Path C:\iso_source\sources\install.*
```

Den tatsächlich vorhandenen Dateipfad setzen. Bei ESD die zweite Variante verwenden:

```powershell
$SourceImage = 'C:\iso_source\sources\install.wim'
# Bei einer ESD stattdessen:
# $SourceImage = 'C:\iso_source\sources\install.esd'

dism /Get-WimInfo "/WimFile:$SourceImage"
if ($LASTEXITCODE -ne 0) { throw 'Editionen konnten nicht gelesen werden.' }
```

Den Index der gewünschten Edition aus dieser Ausgabe übernehmen. Nicht voraussetzen, dass Pro immer denselben Index hat. Danach nur diese Edition in eine **neue** WIM exportieren:

```powershell
[int]$ImageIndex = Read-Host 'Index der gewünschten Edition'
New-Item -Path C:\image_work -ItemType Directory -Force | Out-Null
$SelectedImage = 'C:\image_work\install-selected.wim'
if (Test-Path -LiteralPath $SelectedImage) {
    throw 'Die Zieldatei existiert bereits. Für einen neuen Export einen neuen Dateinamen wählen.'
}

dism /Export-Image "/SourceImageFile:$SourceImage" "/SourceIndex:$ImageIndex" "/DestinationImageFile:$SelectedImage" /Compress:max /CheckIntegrity
if ($LASTEXITCODE -ne 0) { throw 'Image-Export fehlgeschlagen. Quelle unverändert lassen.' }

Copy-Item -LiteralPath $SelectedImage -Destination C:\iso_source\sources\install.wim -Force -ErrorAction Stop
if ($SourceImage -like '*.esd') {
    Remove-Item -LiteralPath $SourceImage -ErrorAction Stop
}
dism /Get-WimInfo /WimFile:C:\iso_source\sources\install.wim
if ($LASTEXITCODE -ne 0) { throw 'Die exportierte WIM konnte nicht geprüft werden.' }
```

Die neu erzeugte WIM enthält genau eine Edition mit **Index 1**. In den weiteren Schritten wird diese Datei verwendet. Die Original-ISO bleibt als Ausgangspunkt erhalten.

`/Delete-Image` entfernt nur Index-/Metadaten und verkleinert die Datei nicht entsprechend. Der Export ist deshalb für eine einzelne Edition geeigneter. Quelle: [DISM, Export-Image und Delete-Image](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-image-management-command-line-options-s14).

---

## 4. Mount-Ordner anlegen und Image mounten

### Vorhandene Mounts prüfen

```powershell
dism /Get-MountedWimInfo
```

Ein bereits bereitgestelltes Image zuerst bewusst mit `/Commit` speichern oder mit `/Discard` verwerfen. Diese Entscheidung betrifft die Änderungen dieses Images:

```powershell
# Nur für das tatsächlich unter C:\mount bereitgestellte Image:
dism /Unmount-Wim /MountDir:C:\mount /Commit
# Alternative ohne Speichern, nicht zusätzlich ausführen:
# dism /Unmount-Wim /MountDir:C:\mount /Discard
```

Bei einem unzugänglichen Mount zunächst `dism /Remount-Image /MountDir:C:\mount` versuchen. `dism /Cleanup-Mountpoints` bereinigt beschädigte Mount-Ressourcen, stellt aber kein reguläres Aushängen dar. Danach den Status erneut prüfen.

**Einen Mount-Ordner niemals mit `Remove-Item` bereinigen, solange dort ein Image bereitgestellt ist.** Für einen neuen Mount einen leeren Ordner verwenden:

```powershell
New-Item -Path C:\mount -ItemType Directory -Force | Out-Null
if (Get-ChildItem -LiteralPath C:\mount -Force -ErrorAction Stop) {
    throw 'Mount-Ordner ist nicht leer. Vorhandenen Mount prüfen oder einen anderen leeren Ordner verwenden.'
}

dism /Mount-Wim /WimFile:C:\iso_source\sources\install.wim /Index:1 /MountDir:C:\mount
if ($LASTEXITCODE -ne 0) { throw 'Image konnte nicht bereitgestellt werden.' }
```

Das Windows-Dateisystem liegt nun unter `C:\mount`. Bei einem anderen Mount-Pfad alle folgenden Befehle entsprechend anpassen.

---

## 5. Funktionen entfernen oder deaktivieren

### Liste der vorinstallierten Apps anzeigen

```powershell
Get-AppxProvisionedPackage -Path C:\mount |
    Sort-Object DisplayName |
    Select-Object DisplayName, PackageName
```

Alternativ mit DISM:

```powershell
dism /Image:C:\mount /Get-ProvisionedAppxPackages
```

### Mögliche Kandidaten zur Entfernung

Die folgende Liste ist eine Auswahl, keine für jede ISO bestätigte Paketliste. Nur tatsächlich vorhandene und für den eigenen Einsatz unerwünschte Pakete entfernen. Zwischen 26H2, 25H2, 24H2 und älteren Images können Namen und Umfang abweichen:

| Anzeigename | Grund |
| ----------- | ----- |
| `Clipchamp.Clipchamp` | Videoeditor mit Online-/Konto-Fokus |
| `Microsoft.BingNews` | Nachrichten-App |
| `Microsoft.BingSearch` | Bing-/Websuche |
| `Microsoft.BingWeather` | Wetter-App |
| `Microsoft.Copilot` | Separate Microsoft-Copilot-App, sofern im Image vorhanden |
| `Microsoft.GamingApp` | Xbox-/Gaming-App |
| `Microsoft.GetHelp` | Online-Hilfe |
| `Microsoft.MicrosoftOfficeHub` | Microsoft-365-/Office-Hub |
| `Microsoft.MicrosoftSolitaireCollection` | Spiel |
| `Microsoft.OutlookForWindows` | Neues Outlook mit Cloud-/Konto-Fokus |
| `Microsoft.PowerAutomateDesktop` | Power Automate Desktop |
| `Microsoft.Todos` | Microsoft To Do |
| `Microsoft.Windows.DevHome` | Dev Home |
| `Microsoft.WindowsFeedbackHub` | Feedback Hub |
| `Microsoft.Xbox.TCUI` | Xbox-Komponente |
| `Microsoft.XboxGamingOverlay` | Xbox Game Bar |
| `Microsoft.XboxIdentityProvider` | Xbox-Anmeldung |
| `Microsoft.XboxSpeechToTextOverlay` | Xbox-Sprachkomponente |
| `Microsoft.YourPhone` | Smartphone-Link |
| `Microsoft.ZuneMusic` | Medien-App/Groove-Nachfolger |
| `MicrosoftCorporationII.QuickAssist` | Remotehilfe |
| `MicrosoftWindows.Client.WebExperience` | Windows Web Experience Pack, unter anderem für Widgets. Keine allgemeine Copilot-Sperre. |
| `MicrosoftWindows.CrossDevice` | Geräteübergreifende Integration |
| `MSTeams` | Microsoft Teams |

Optional zusätzlich entfernbar, wenn diese Funktionen sicher nicht gebraucht werden:

| Anzeigename | Auswirkung |
| ----------- | ---------- |
| `Microsoft.MicrosoftStickyNotes` | Keine Sticky Notes |
| `Microsoft.Windows.Photos` | Keine moderne Fotos-App |
| `Microsoft.WindowsAlarms` | Keine Uhr-/Alarm-App |
| `Microsoft.WindowsCamera` | Keine Kamera-App |
| `Microsoft.WindowsSoundRecorder` | Kein Sprachrekorder |

Diese Pakete besser behalten, damit Basisfunktionen, Store-/Winget-Infrastruktur, Sicherheit und Medienformate nicht unnötig beschädigt werden:

```text
Microsoft.ApplicationCompatibilityEnhancements
Microsoft.AV1VideoExtension
Microsoft.AVCEncoderVideoExtension
Microsoft.DesktopAppInstaller
Microsoft.HEIFImageExtension
Microsoft.HEVCVideoExtension
Microsoft.MPEG2VideoExtension
Microsoft.Paint
Microsoft.RawImageExtension
Microsoft.ScreenSketch
Microsoft.SecHealthUI
Microsoft.StorePurchaseApp
Microsoft.VP9VideoExtensions
Microsoft.WebMediaExtensions
Microsoft.WebpImageExtension
Microsoft.WindowsCalculator
Microsoft.WindowsNotepad
Microsoft.WindowsStore
Microsoft.WindowsTerminal
```

### Unerwünschte Apps entfernen

Die Auswahl erfolgt über `DisplayName`, sodass geänderte Paketversionsnummern nicht einzeln eingetragen werden müssen. Ein geänderter DisplayName muss dagegen in der Liste angepasst werden. Das Entfernen eines provisionierten Pakets verhindert die anfängliche Bereitstellung für neue Benutzer. Es verhindert keine spätere Neuinstallation über Store, Verwaltung oder geänderte Windows-Updates:

```powershell
$AppsToRemove = @(
    'Clipchamp.Clipchamp',
    'Microsoft.BingNews',
    'Microsoft.BingSearch',
    'Microsoft.BingWeather',
    'Microsoft.Copilot',
    'Microsoft.GamingApp',
    'Microsoft.GetHelp',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.OutlookForWindows',
    'Microsoft.PowerAutomateDesktop',
    'Microsoft.Todos',
    'Microsoft.Windows.DevHome',
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.Xbox.TCUI',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.YourPhone',
    'Microsoft.ZuneMusic',
    'MicrosoftCorporationII.QuickAssist',
    'MicrosoftWindows.Client.WebExperience',
    'MicrosoftWindows.CrossDevice',
    'MSTeams'
)

$ProvisionedPackages = Get-AppxProvisionedPackage -Path C:\mount

foreach ($App in $AppsToRemove) {
    $PackagesForApp = $ProvisionedPackages | Where-Object { $_.DisplayName -eq $App }

    if (-not $PackagesForApp) {
        Write-Host "Schon entfernt oder nicht in dieser ISO vorhanden: $App"
        continue
    }

    foreach ($Package in $PackagesForApp) {
        Write-Host "Entferne: $($Package.DisplayName) [$($Package.PackageName)]"
        Remove-AppxProvisionedPackage -Path C:\mount -PackageName $Package.PackageName -ErrorAction Stop
    }
}
```

Danach erneut prüfen:

```powershell
Get-AppxProvisionedPackage -Path C:\mount |
    Sort-Object DisplayName |
    Select-Object DisplayName, PackageName
```

---

## 6. Cloud-Integration und Recall gezielt konfigurieren

Richtlinien gelten nur für die von Microsoft dokumentierten Versionen und Editionen. Ein erfolgreich geschriebener Registry-Wert bestätigt nicht, dass die installierte Edition ihn auswertet. Die Beispiele zielen auf Pro sowie Enterprise/Education. Bei Home ist keine entsprechende Richtlinienwirkung zugesagt.

### Offline-Registry laden, bearbeiten und entladen

Dieser Block verändert ausschließlich die SOFTWARE-Hive des bereitgestellten Images. `HKLM\WIM` darf vorher nicht anderweitig verwendet werden. Die Hive wird auch bei einem Fehler im `finally`-Block wieder entladen.

```powershell
reg load HKLM\WIM C:\mount\Windows\System32\config\SOFTWARE
if ($LASTEXITCODE -ne 0) { throw 'Offline-Registry konnte nicht geladen werden.' }
try {
    # Geräteübergreifende Cloud-Zwischenablage deaktivieren
    reg add 'HKLM\WIM\Policies\Microsoft\Windows\System' /v AllowCrossDeviceClipboard /t REG_DWORD /d 0 /f
    if ($LASTEXITCODE -ne 0) { throw 'Cloud-Zwischenablage konnte nicht konfiguriert werden.' }

    # Online-Tipps deaktivieren
    reg add 'HKLM\WIM\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v AllowOnlineTips /t REG_DWORD /d 0 /f
    if ($LASTEXITCODE -ne 0) { throw 'Online-Tipps konnten nicht konfiguriert werden.' }

    # Veröffentlichung und Upload von Benutzeraktivitäten unterbinden,
    # soweit diese Funktionen in der Zielversion vorhanden sind
    reg add 'HKLM\WIM\Policies\Microsoft\Windows\System' /v EnableActivityFeed /t REG_DWORD /d 0 /f
    if ($LASTEXITCODE -ne 0) { throw 'Aktivitätsfeed konnte nicht konfiguriert werden.' }
    reg add 'HKLM\WIM\Policies\Microsoft\Windows\System' /v PublishUserActivities /t REG_DWORD /d 0 /f
    if ($LASTEXITCODE -ne 0) { throw 'Veröffentlichung von Aktivitäten konnte nicht konfiguriert werden.' }
    reg add 'HKLM\WIM\Policies\Microsoft\Windows\System' /v UploadUserActivities /t REG_DWORD /d 0 /f
    if ($LASTEXITCODE -ne 0) { throw 'Upload von Aktivitäten konnte nicht konfiguriert werden.' }
}
finally {
    reg unload HKLM\WIM
    if ($LASTEXITCODE -ne 0) { throw 'HKLM\WIM konnte nicht entladen werden. Image noch nicht aushängen.' }
}
```

Die Cloud-Zwischenablage wird über `AllowCrossDeviceClipboard` im Richtlinienpfad `Software\Policies\Microsoft\Windows\System` gesteuert. Der lokale Zwischenablageverlauf ist eine eigene Einstellung. Quelle: [Microsoft, Privacy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#allowcrossdeviceclipboard). Die Online-Tipps der Einstellungen verwenden dagegen `Software\Microsoft\Windows\CurrentVersion\Policies\Explorer`, siehe [Microsoft, AllowOnlineTips](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-settings#allowonlinetips).

### Optional: Recall-Schnappschüsse unterbinden

`DisableAIDataAnalysis` verhindert das Speichern von Recall-Schnappschüssen, sofern die Zielversion und Edition die Richtlinie unterstützen. Microsoft nennt für Windows 11 24H2 mindestens Build **26100.3915** mit KB5055627. Für 25H2 und 26H2 die dokumentierte Anwendbarkeit am jeweiligen Zielstand prüfen. Dies ist keine allgemeine Abschaltung sämtlicher KI-Funktionen und deinstalliert Recall nicht.

Nur für ein geeignetes Zielimage ergänzen:

```powershell
reg load HKLM\WIM C:\mount\Windows\System32\config\SOFTWARE
if ($LASTEXITCODE -ne 0) { throw 'Offline-Registry konnte nicht geladen werden.' }
try {
    reg add 'HKLM\WIM\Policies\Microsoft\Windows\WindowsAI' /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f
    if ($LASTEXITCODE -ne 0) { throw 'Recall-Richtlinie konnte nicht gesetzt werden.' }
}
finally {
    reg unload HKLM\WIM
    if ($LASTEXITCODE -ne 0) { throw 'HKLM\WIM konnte nicht entladen werden. Image noch nicht aushängen.' }
}
```

Quelle: [Microsoft, WindowsAI CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai#disableaidataanalysis).

### Copilot und Websuche gesondert behandeln

Die ältere Benutzerrichtlinie `TurnOffWindowsCopilot` ist keine wirksame pauschale Sperre für die neue Copilot-App. Sie gehört außerdem zum Benutzerkontext, nicht in die hier geladene SOFTWARE-Hive als Computerrichtlinie. Für die neue App die Entfernung in Abschnitt 5 verwenden und bei Bedarf eine zur Edition passende App-Steuerung einrichten. Copilot in Edge, Microsoft 365 und anderen Anwendungen benötigt jeweils eigene Einstellungen.

Auch die früher verwendeten Suchwerte `ConnectedSearchUseWeb`, `DisableWebSearch` oder ein im falschen Kontext gesetztes `DisableSearchBoxSuggestions` werden hier nicht mehr als allgemeine Websuchsperre empfohlen. Suchrichtlinien haben eigene Versions-, Editions- und Kontextgrenzen. Der Verzicht auf die Bing-App allein schaltet nicht sämtliche Websuchfunktionen von Windows aus. Eine gewünschte Websuchsperre muss nach der Installation für die konkrete Version separat eingerichtet und geprüft werden.

Quellen: [Microsoft, TurnOffWindowsCopilot](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai#turnoffwindowscopilot), [Microsoft, Search CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search).

---

## 7. Systemeinstellungen beim Setup anwenden

Das mitgelieferte [Configure-Windows.cmd](scripts/Configure-Windows.cmd) wird im Konfigurationsdurchlauf **specialize** über die Antwortdatei aufgerufen. Es läuft dabei im Systemkontext. Dieser Weg vermeidet die Einschränkung von `SetupComplete.cmd`: Windows Setup führt SetupComplete bei einem OEM-Produktschlüssel unter anderem auf Pro nicht aus. Enterprise und Windows Server sind von dieser konkreten Einschränkung ausgenommen. Quelle: [Microsoft, Add a custom script to Windows Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup).

Den folgenden Kopierbefehl **aus dem Projektverzeichnis** ausführen, während das Image unter `C:\mount` bereitgestellt ist:

```powershell
New-Item -Path C:\mount\Windows\Setup\Scripts -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath .\scripts\Configure-Windows.cmd -Destination C:\mount\Windows\Setup\Scripts\Configure-Windows.cmd -Force -ErrorAction Stop
```

Das Skript setzt unter anderem die dokumentierte Werbe-ID-Richtlinie `DisabledByGroupPolicy`, reduziert Diagnose- und Feedbackeinstellungen und deaktiviert den Start vorhandener Diagnosedienste. Bereits laufende Dienste werden dabei nicht gestoppt. Es schreibt sein Ergebnis nach `%WINDIR%\Setup\Scripts\Configure-Windows.log`.

Die Diagnosedatenstufe wird editionsabhängig gesetzt: Pro erhält `AllowTelemetry=1`, unterstützte Enterprise-/Education-Editionen erhalten `0`. Stufe 0 ist für Pro keine zugesagte Abschaltung von Diagnosedaten. Die Consumer-Richtlinien `DisableWindowsConsumerFeatures` und `DisableSoftLanding` setzt das Skript nur für die dafür vorgesehenen Enterprise-/Education-Editionen. Fehlende Dienste werden protokolliert und übersprungen.

**Auswirkung auf OneDrive:** `DisableFileSyncNGSC=1` sperrt die Nutzung von OneDrive zur Dateispeicherung und Synchronisierung, einschließlich Arbeits- und Schulkonten. Das ist mehr als eine Autostart-Einstellung. Wenn OneDrive benötigt wird, diese Zeile im Skript vor dem Kopieren entfernen. Das Skript reduziert außerdem Edge-Hintergrundaktivität und schließt Edge-Experimente aus, behält dabei den Bezug von Kompatibilitätskonfigurationen bei.

Für die automatische Ausführung ist die `specialize`-Konfiguration der mitgelieferten `autounattend.xml` aus Abschnitt 11 erforderlich. Wer keine Antwortdatei verwendet, kann das kopierte Skript nach der Installation in einer als Administrator geöffneten PowerShell manuell starten:

```powershell
& "$env:WINDIR\Setup\Scripts\Configure-Windows.cmd"
```

Die Deaktivierung von Diagnosediensten kann Diagnosefunktionen einschränken. Gewünschtes Verhalten und Richtlinienwirkung nach der Testinstallation prüfen. Quellen: [Microsoft, System CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-system#allowtelemetry), [Microsoft, Experience CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowsconsumerfeatures), [Microsoft, Privacy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#disableadvertisingid).

---

## 8. OOBE und lokales Konto

Für die geplante lokale Kontoanlage einen Benutzer in `autounattend.xml` gemäß Abschnitt 11.7 ergänzen. Die mitgelieferte Basisdatei enthält bewusst weder Konto noch Passwort oder automatische Anmeldung. Ohne Ergänzung können Kontodialoge weiterhin erscheinen.

`HideOnlineAccountScreens=true` ersetzt keine Kontoanlage. Veraltete BypassNRO-Tricks werden nicht als versionsübergreifende Grundlage eingesetzt. Ob das gesamte OOBE mit der gewünschten Netzwerkverbindung durchläuft, muss mit der konkreten 26H2-, 25H2- oder älteren ISO geprüft werden.

Die Antwortdatei partitioniert keine Datenträger und automatisiert nicht die gesamte Installation. Die Auswahl des Installationsziels bleibt interaktiv. Ein angelegter Benutzer wird außerdem nicht automatisch angemeldet. Dafür wäre eine separate AutoLogon-Konfiguration nötig, die hier nicht vorgesehen ist.

---

## 9. Image unmounten

### Mit Änderungen speichern

```powershell
dism /Unmount-Wim /MountDir:C:\mount /Commit
if ($LASTEXITCODE -ne 0) { throw 'Image konnte nicht mit Änderungen ausgehängt werden.' }
```

### Alternative: ohne Speichern verwerfen

Diese Alternative nur ausführen, wenn die Änderungen verworfen werden sollen. Nicht zusätzlich zum erfolgreichen Speichern ausführen.

```powershell
dism /Unmount-Wim /MountDir:C:\mount /Discard
```

---

## 10. Windows ADK installieren

Für die grundlegenden DISM-Arbeiten stehen Windows-Bordmittel zur Verfügung. Eine neue bootfähige ISO wird hier mit `oscdimg.exe` aus den **Bereitstellungstools (Deployment Tools)** des ADK erzeugt. Windows SIM dient zum Erstellen und Prüfen der Antwortdatei. Das separate WinPE-Add-on ist für diesen Ablauf mit einer vorhandenen Microsoft-Installationsquelle nicht erforderlich.

### Passende ADK-Version und Wartung auswählen

Microsoft bietet für **26H2, 25H2 und 24H2** das **ADK 10.1.26100.9457 (September 2026)** an. Für 23H2 oder ältere Zielimages die Kompatibilität auf der Downloadseite prüfen. Nicht einfach annehmen, dass jedes neue ADK jeden alten Katalog unterstützt.

Vor der Installation die [aktuelle Microsoft-ADK-Seite](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) aufrufen. Danach die [ADK-Wartungshinweise](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-servicing) prüfen und nur einen ausdrücklich für die installierte ADK-Version vorgesehenen Patch anwenden. Ein auf der Wartungsseite noch für **10.1.26100.2454** genannter Patch wie **KB5101684** ist kein pauschal passendes Update für **10.1.26100.9457**.

### Installation der Bereitstellungstools

PowerShell als Administrator öffnen. Der Microsoft-Weiterleitungslink kann künftig eine neuere Version liefern; Version und digitale Signatur vor der Installation kontrollieren:

```powershell
$AdkSetup = "$env:TEMP\adksetup.exe"
Invoke-WebRequest `
    -Uri 'https://go.microsoft.com/fwlink/?linkid=2289980' `
    -OutFile $AdkSetup

(Get-Item -LiteralPath $AdkSetup).VersionInfo | Select-Object ProductVersion, FileVersion
Get-AuthenticodeSignature -LiteralPath $AdkSetup | Select-Object Status, SignerCertificate
```

Erst nach Prüfung mit dem gewünschten Installer fortfahren:

```powershell
$AdkProcess = Start-Process `
    -FilePath $AdkSetup `
    -ArgumentList '/quiet /features OptionId.DeploymentTools /ceip off /norestart' `
    -WindowStyle Hidden -Wait -PassThru
if ($AdkProcess.ExitCode -notin @(0, 3010)) { throw "ADK-Installation fehlgeschlagen: $($AdkProcess.ExitCode)" }
if ($AdkProcess.ExitCode -eq 3010) { Write-Host 'Neustart erforderlich.' }
```

Anschließend gegebenenfalls den ausdrücklich passenden Wartungspatch nach Microsoft-Anleitung installieren. Keine KB aus einer anderen ADK-Versionsreihe erzwingen.

### Installationspfade prüfen

```powershell
Test-Path 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
Test-Path 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\WSIM\imgmgr.exe'
```

Für Abschnitt 12 ist `oscdimg.exe` nötig. Windows SIM wird in Abschnitt 11 zur Prüfung der Antwortdatei verwendet.

---

## 11. Autounattend.xml verwenden oder weglassen

Die Antwortdatei steuert Sprache, Installationsschlüssel und ausgewählte OOBE-Dialoge. Die mitgelieferte Datei ruft außerdem das Skript aus Abschnitt 7 im Durchlauf `specialize` auf. Für dessen automatische Ausführung ist sie daher Teil des hier beschriebenen Ablaufs. Das reine Entfernen von Apps aus der WIM und das Erzeugen einer ISO sind auch ohne Antwortdatei möglich.

Die [mitgelieferte Basisdatei](autounattend.xml) **aus dem Projektverzeichnis** kopieren:

```powershell
Copy-Item -LiteralPath .\autounattend.xml -Destination C:\iso_source\autounattend.xml -Force -ErrorAction Stop
[xml](Get-Content -LiteralPath C:\iso_source\autounattend.xml -Raw -Encoding UTF8) | Out-Null
```

Die XML-Prüfung bestätigt nur die Wohlgeformtheit, nicht die Gültigkeit für das Zielimage. Die Datei ist für deutschsprachiges Windows 11 Pro mit amd64-Komponenten vorbereitet und enthält einen generischen Pro-Installationsschlüssel. Dieser aktiviert Windows nicht. Für eine andere Edition müssen Schlüssel und Komponentenauswahl angepasst werden.

**Vor Verwendung anpassen und prüfen:** Kontoanlage gemäß Abschnitt 11.7 ergänzen, falls gewünscht. Das Skript aus Abschnitt 7 muss im Image vorhanden sein. Wird das Skript nicht verwendet, den zugehörigen `Microsoft-Windows-Deployment`-Eintrag im Durchlauf `specialize` aus der Antwortdatei entfernen. Anschließend mit Windows SIM gegen genau das verwendete Image validieren.

Wer ganz auf die Antwortdatei verzichtet, erhält die normalen interaktiven Setup-Dialoge und muss das Skript bei Bedarf nachträglich starten. Die folgenden SIM-Schritte erklären das Prüfen und Anpassen der Vorlage sowie das Erstellen einer eigenen Datei.

### 11.1 Windows SIM starten

Nach der Installation des ADK befindet sich das Tool hier:

**Startmenü** → **Windows Kits** → **Windows System Image Manager**

![SIM](bilder/sim.png)

### 11.2 Windows Image laden

1. Im linken Bereich unter **Windows Image** auf „Windows Image oder Katalogdatei auswählen“ klicken
2. Die Datei auswählen: `C:\iso_source\sources\install.wim`
3. Wenn das Tool fragt, ob eine Katalogdatei erstellt werden soll, mit **„Ja“** bestätigen

Die Erstellung kann einige Minuten dauern.

### 11.3 Antwortdatei öffnen oder neu anlegen

Für die Vorlage **Datei** → **Antwortdatei öffnen** wählen und `C:\iso_source\autounattend.xml` öffnen. Nur für eine vollständig neue Datei **Datei** → **Neue Antwortdatei** wählen.

Im rechten Bereich erscheinen die Konfigurationsdurchläufe:

1. windowsPE
2. offlineServicing
3. generalize
4. specialize
5. auditSystem
6. auditUser
7. oobeSystem

Bei einer eigenen neu erstellten Antwortdatei zusätzlich die Komponente `amd64_Microsoft-Windows-Deployment_neutral` aus dem geladenen Image zu **4 specialize** hinzufügen. Unter `RunSynchronous` einen `RunSynchronousCommand` mit `Order=1` und folgendem `Path` anlegen:

```text
cmd /c "%WINDIR%\Setup\Scripts\Configure-Windows.cmd"
```

Dieser Eintrag entspricht der mitgelieferten XML. Ohne ihn wird das Skript nicht automatisch ausgeführt. Quelle: [Microsoft, RunSynchronous](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous).

### 11.4 Sprach- und Regionseinstellungen hinzufügen
Für den Start der Installation ist **windowsPE** der relevante Abschnitt

1. Komponente im Windows Image-Bereich suchen:  
   `amd64_Microsoft-Windows-International-Core-WinPE_neutral`

2. Anklicken und zu **Components → 1 windowsPE** ziehen

Für die automatische Installation ist **oobeSystem** der relevante Abschnitt.

3. Komponente im Windows Image-Bereich suchen:  
   `amd64_Microsoft-Windows-International-Core_neutral`

4. Anklicken und zu **Components → 7 oobeSystem** ziehen

Für beide Komponenten:

5. Eigenschaften setzen:
   - `InputLocale = 0407:00000407`
   - `SystemLocale = de-DE`
   - `UILanguage = de-DE`
   - `UserLocale = de-DE`

### 11.5 Windows Produkt-Key hinzufügen
Damit die Installation keine Abfrage nach einem Product-Key anzeigt, wird ein generischer Installationsschlüssel eingetragen. Dieser Schlüssel dient ausschließlich zur Installation und aktiviert Windows nicht.

1. Komponente im Windows Image-Bereich suchen:
   `amd64_Microsoft-Windows-Setup_neutral`

2. Anklicken und zu **Components → 1 windowsPE** ziehen

3. Produkt-Key eintragen

Unter Microsoft-Windows-Setup → UserData:
   - `AcceptEula=true`
überspringt die EULA-Anzeige

Unter Microsoft-Windows-Setup → UserData → ProductKey:
   - `Key=VK7JG-NPHTM-C97JM-9MPGT-3V66T`
   - `WillShowUI=Never`
(Generischer Windows 11 Pro Installationsschlüssel)
verhindert die Key-Abfrage

WillShowUI: Never

### 11.6 Shell Setup für OOBE hinzufügen

1. Komponente suchen:  
   `amd64_Microsoft-Windows-Shell-Setup_10.0.x_neutral`

   Die Komponente aus dem Katalog des tatsächlich verwendeten Zielimages wählen. Architektur und Katalog müssen dazu passen, nicht einfach die höchste irgendwo vorhandene Buildnummer auswählen.

2. Anklicken und auch zu **Components → 7 oobeSystem** ziehen

3. In der Antwortdatei den Knoten der Shell Setup-Komponente aufklappen (Plus drücken)

4. Unterpunkt **„OOBE“** auswählen und die Werte setzen:
 
| Einstellung                   | Wert    | Erklärung                                                                |
| ----------------------------- | ------- | ------------------------------------------------------------------------ |
| **HideEULAPage**              | `true`  | Blendet die EULA Seite aus                                               |
| **HideLocalAccountScreen**    |         | Für Windows 11 Pro nicht relevant; diese Einstellung gilt nur für Windows Server |
| **HideOEMRegistrationScreen** | `true`  | OEM Registrierungsseite wird nicht angezeigt                             |
| **HideOnlineAccountScreens**  | `true`  | Blendet unterstützte Online-Kontodialoge aus, legt kein Konto an           |
| **HideWirelessSetupInOOBE**   | `true`  | Unterdrückt WLAN Setup Seiten                                            |
| **NetworkLocation**           |         | Veraltete Einstellung. Für diese Windows-11-Vorlage nicht setzen. |
| **OEMAppId**                  |         | Wird von PC Herstellern genutzt, für normale Installationen leer lassen. |
| **ProtectYourPC**             | `3`     | Aktiviert die Express-Einstellungen nicht. Dies ersetzt keine Diagnosedatenrichtlinie. |
| **SkipMachineOOBE**           |         | Nicht setzen. Microsoft empfiehlt diese Einstellung nicht zur OOBE-Automatisierung. |
| **SkipUserOOBE**              |         | Nicht setzen. Gewünschte OOBE-Seiten einzeln konfigurieren. |
| **UnattendEnableRetailDemo**  |         | Nicht setzen. Die Vorlage richtet keinen Retail-Demomodus ein. |

Diese Konfiguration reduziert Interaktionen, soweit Windows Setup das für die verwendete ISO zulässt. Die Kontodialoge werden dadurch nicht versionsunabhängig vollständig automatisiert. Für die gewünschte lokale Kontoanlage einen Benutzer ergänzen. Zu `ProtectYourPC`: [Microsoft-Dokumentation](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc).

### 11.7 Lokalen Administrator automatisch anlegen

Die mitgelieferte Basisdatei enthält keinen Benutzer. Für eine automatische lokale **Kontoanlage** muss unter `Microsoft-Windows-Shell-Setup` ein lokales Konto ergänzt werden. Das richtet keine automatische Anmeldung ein. Ohne Kontoanlage können die Kontodialoge während OOBE weiterhin erscheinen.

In der Antwortdatei den Knoten der Shell Setup-Komponente erweitern.
Pfad:
Components → 7 oobeSystem → Microsoft-Windows-Shell-Setup → UserAccounts → LocalAccounts

Rechtsklick und „Neuen LocalAccount einfügen“ auswählen.

Für den lokalen Administrator folgende Werte setzen:
| Einstellung     | Wert            | Erklärung                                              |
| --------------- | --------------- | ------------------------------------------------------ |
| **Action**      | AddListItem     | Legt einen neuen Benutzer an                           |
| **Description** | optional        | Beschreibung des Kontos, meist leer                    |
| **DisplayName** | Niko            | Anzeigename des Nutzers                                |
| **Group**       | Administrators | Ordnet den Benutzer der lokalen Administratorgruppe zu |
| **Name**        | Niko            | Benutzername des Kontos                                |

Der technische Gruppenname muss **`Administrators`** lauten, auch auf einem deutschsprachigen Windows. Windows ordnet ihn der passenden lokalen Gruppe zu. Quelle: [Microsoft, LocalAccount Group](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts-localaccount-group).

Dann bei `LocalAccount` auf das Plus-Symbol klicken und bei `Password` die Werte setzen:

| Einstellung   | Wert         |
| ------------- | ------------ |
| **Value**     | das Passwort |
| **PlainText** | `true`       |

**Wichtig:** Für jeden Einsatz ein geeignetes eigenes Passwort setzen. Eine Datei mit `PlainText=true` enthält es lesbar. Auch die von Windows SIM verwendete Verschleierung ist keine Verschlüsselung. Eine angepasste Antwortdatei mit echten Zugangsdaten nicht ins öffentliche Repository hochladen. Das Installationsmedium entsprechend schützen und eingebettete Kennwörter nach der Bereitstellung ändern.

### 11.8 Antwortdatei speichern

**Menü** → **Datei** → **Antwortdatei speichern unter**

**Dateiname:** `C:\iso_source\autounattend.xml`

**Wichtig:** Der Name muss unverändert bleiben, da Windows Setup die Datei automatisch einliest.

Vor dem Einsatz **Extras → Antwortdatei überprüfen** (englisch: **Tools → Validate Answer File**) ausführen. Fehler und Warnungen anhand des tatsächlich geladenen Zielimages bearbeiten. Danach speichern und die Installation in einer virtuellen Maschine testen. Windows Setup liest eine korrekt benannte Datei im Stamm des Installationsmediums automatisch ein; die hier enthaltenen Antworten automatisieren nur die konfigurierten Teile des Setups.

---

## 12. ISO erzeugen (optional)

Diesen Schritt nur ausführen, wenn aus `C:\iso_source` wieder eine bootfähige ISO-Datei erstellt werden soll. Vorher das Image mit `/Commit` aushängen und sicherstellen, dass `HKLM\WIM` nicht mehr geladen ist. Antwortdatei und Skript müssen bereits an den vorgesehenen Orten liegen.

Die Bootdateien müssen aus der zur Zielversion gehörenden Installationsquelle stammen. Das Erzeugen einer ISO mit `oscdimg` ersetzt oder aktualisiert keine Secure-Boot-Zertifikate. Für deren Auswahl gilt Abschnitt 13.

```powershell
$Oscdimg = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
foreach ($RequiredFile in @($Oscdimg, 'C:\iso_source\boot\etfsboot.com', 'C:\iso_source\efi\microsoft\boot\efisys.bin')) {
    if (-not (Test-Path -LiteralPath $RequiredFile -PathType Leaf)) {
        throw "Benötigte Datei fehlt: $RequiredFile"
    }
}
if (Test-Path -LiteralPath C:\Win11_Custom.iso) {
    throw 'Die Zieldatei C:\Win11_Custom.iso existiert bereits. Vorhandene ISO zuerst prüfen oder einen anderen Zielnamen verwenden.'
}
& $Oscdimg -m -o -u2 -udfver102 '-bootdata:2#p0,e,bC:\iso_source\boot\etfsboot.com#pEF,e,bC:\iso_source\efi\microsoft\boot\efisys.bin' C:\iso_source C:\Win11_Custom.iso
if ($LASTEXITCODE -ne 0) { throw 'ISO-Erstellung fehlgeschlagen.' }
```

---

## 13. ISO auf USB-Stick schreiben und testen

Für die angepasste ISO Rufus verwenden. Das Microsoft Media Creation Tool erzeugt ein neues Microsoft-Installationsmedium und übernimmt diese angepasste ISO nicht.

### Rufus installieren und starten

```powershell
winget install --id Rufus.Rufus -e
```

Rufus anschließend über das Startmenü oder die installierte Anwendung starten. Ein Befehl `rufus` ist nicht bei jeder Installationsart automatisch im PATH vorhanden. Eine aktuelle Version verwenden, besonders für neue Windows-Versionen und die Secure-Boot-Zertifikatsumstellung.

### Einstellungen in Rufus

- **Gerät:** den vorgesehenen USB-Stick sorgfältig auswählen.
- **Startart:** `C:\Win11_Custom.iso` auswählen.
- **Image-Eigenschaft:** Standard Windows installation.
- **Partitionsschema:** GPT.
- **Zielsystem:** UEFI.
- **Dateisystem:** nach Rufus-Vorgabe, bei einer WIM über 4 GB üblicherweise NTFS mit UEFI:NTFS.

Mit **Start** wird der ausgewählte Stick formatiert und sein Inhalt gelöscht.

### Eine Quelle für Setup-Antworten verwenden

Mit der eigenen `autounattend.xml` aus Abschnitt 11 keine zusätzlichen Rufus-Anpassungen für Kontoanlage, Region, Datenschutz oder Komfort-Einstellungen aktivieren. Rufus kann für seine Windows-Anpassungen ebenfalls Antwortdateien erzeugen. Windows Setup wertet diese nach einer Suchreihenfolge aus und führt sie nicht automatisch zusammen. Entweder die eigene geprüfte Datei verwenden oder die Einrichtung von Rufus erzeugen lassen. Nach dem Schreiben die eigene Stammdatei und gegebenenfalls zusätzliche Antwortdateien kontrollieren, insbesondere den `specialize`-Aufruf und die vorgesehenen Kontoeinstellungen. Quellen: [Rufus, Antwortdateien](https://github.com/pbatard/rufus/blob/master/src/wue.c), [Microsoft, Suchreihenfolge](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview#implicit-answer-file-search-order).

Die angebotenen Optionen unterscheiden sich nach Rufus-Version und ausgewählter ISO. Es gibt daher keine für alle 26H2-, 25H2- und älteren Medien gültige Liste anzukreuzender Felder.

| Option | Verwendung |
| ------ | ---------- |
| Online-Microsoft-Konto entfernen, lokales Benutzerkonto erstellen | Mit eigener Antwortdatei nicht zusätzlich aktivieren. Das gewünschte lokale Konto dort anlegen und testen. |
| Regionale Optionen übernehmen, Datenerfassung deaktivieren, Komfort-Einstellungen | Mit eigener Antwortdatei nicht pauschal zusätzlich aktivieren. Die eigene Konfiguration und das kopierte Skript verwenden. |
| Anforderung für RAM, Secure Boot und TPM 2.0 entfernen | Nur bei bewusst geplanter Installation auf nicht unterstützter Hardware. Das ersetzt keine Hardwareunterstützung und keine fehlenden CPU-Funktionen. Für unterstützte Zielgeräte nicht nötig. |
| Automatische BitLocker-Laufwerksverschlüsselung deaktivieren | Nach dem gewünschten Verschlüsselungskonzept entscheiden. Bei Verwendung von BitLocker die Wiederherstellungsschlüssel vor der Bereitstellung sicher hinterlegen. |
| Den „Windows CA 2023“ signierten Bootloader verwenden | Nach Zertifikatsstand und Rufus-Unterstützung auswählen, siehe unten. Keine pauschale Vorgabe für alle Geräte. |
| SkuSiPolicy.p7b auf Installation anwenden | Nur im Rahmen einer gezielten Secure-Boot-Mitigation nach Microsoft-Anleitung und Test. Die Änderungen können mit UEFI-Sperren verbunden sein. |

### Secure Boot und Windows-CA-2023-Bootloader

Die alte pauschale Empfehlung, die CA-2023-Option immer auszuschalten, gilt nicht. Nach dem Widerruf des bisherigen **Microsoft Windows Production PCA 2011** können damit signierte Installationsmedien unter Secure Boot nicht mehr starten. Für einen mit **Windows UEFI CA 2023** signierten Bootloader muss das Zielgerät seinerseits das neue Zertifikat in der Secure-Boot-Datenbank besitzen.

| Zertifikatsstand des Zielgeräts bei aktiviertem Secure Boot | Auswahl |
| ---------------------------------------------------------- | ------- |
| PCA 2011 widerrufen, CA 2023 wird vertraut | Passendes CA-2023-Medium erforderlich. Das bisherige Medium kann nicht mehr starten. |
| CA 2023 wird noch nicht vertraut | CA-2023-Medium startet nicht. Zertifikatsstand und passendes Medium zuerst klären. |
| Beide Signaturen werden akzeptiert | Nach dem geplanten Zertifikatswechsel entscheiden und auf dem Zielgerät testen. |

Die [Rufus-FAQ](https://github.com/pbatard/rufus/wiki/FAQ#how-do-i-secure-a-pc-for-the-pca-2011-windows-uefi-certificate-revocation-and-install-windows-11-25h2-on-it) beschreibt den entsprechenden Rufus-Weg ausdrücklich für **Windows 11 25H2 ab Rufus 4.10** und schließt **24H2** für diesen Weg aus. Diese Aussage nicht automatisch auf 26H2 oder ältere ISOs übertragen. Für **26H2** mit einer aktuellen Rufus-Version prüfen, welche Option für das konkrete Medium angeboten und unterstützt wird, und auf dem Zielgerät testen.

Bei 24H2 oder älteren Medien einen für diese Version dokumentierten Aktualisierungsweg verwenden, falls die vorhandenen Bootdateien nicht zum Zertifikatsstand passen. Keine Bootdateien verschiedener Windows-Versionen ungeprüft mischen. Secure Boot nicht pauschal als Ersatz für passende Medien abschalten. Microsoft beschreibt die Zertifikatsumstellung und die erforderlichen Schritte in [KB5025885](https://support.microsoft.com/help/5025885).

### Vor der Bereitstellung prüfen

1. ISO zuerst in einer virtuellen Maschine mit UEFI und dem vorgesehenen Secure-Boot-Status starten. Danach den USB-Stick auf einem repräsentativen Zielgerät testen.
2. In Windows SIM die Antwortdatei gegen die konkret verwendete WIM validieren. Beim Setup die gewünschte Edition und den Installationsdatenträger prüfen.
3. Die Einrichtung mit der vorgesehenen Netzwerkverbindung durchspielen. Gewünschte lokale Kontoanlage und Administratorrechte prüfen. Ohne ergänztes Konto keine vollständig automatisierte Kontoanlage erwarten.
4. Nach dem Setup `%WINDIR%\Setup\Scripts\Configure-Windows.log` auf Fehler prüfen. Die tatsächlich angewendeten Richtlinien, verbleibenden Apps, OneDrive-Nutzung und Diagnosedienste kontrollieren.
5. Windows-Version mit `winver`, Aktivierung, Windows Update und die für den Einsatzzweck benötigten Funktionen prüfen. Ein generischer Installationsschlüssel ersetzt keine Lizenz.
6. Für jede weitere Zielversion und Edition den Test wiederholen. Ein erfolgreicher 26H2-Test ist kein Nachweis für 25H2, 24H2 oder ältere Medien.

---

## 14. Zusätzliche Quellen

- [Microsoft, Windows 11 herunterladen](https://www.microsoft.com/de-de/software-download/windows11)
- [Microsoft, Windows-11-Versionen und Support](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Microsoft, ADK herunterladen und Kompatibilität prüfen](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
- [Microsoft, ADK-Wartung](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-servicing)
- [Microsoft, DISM-Imageverwaltung](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-image-management-command-line-options-s14)
- [Microsoft, Get-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/get-appxprovisionedpackage)
- [Microsoft, Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage)
- [Microsoft, OOBE automatisieren](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)
- [Microsoft, RunSynchronous im specialize-Durchlauf](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous)
- [Microsoft, SetupComplete und OEM-Einschränkung](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup)
- [Microsoft, WindowsAI-Richtlinien](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai)
- [Microsoft, Privacy-Richtlinien](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy)
- [Microsoft, Experience-Richtlinien und Editionsgrenzen](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience)
- [Microsoft, Maßnahmen für Secure-Boot-Widerrufe, KB5025885](https://support.microsoft.com/help/5025885)
- [Rufus](https://rufus.ie/)
- [Rufus-FAQ](https://github.com/pbatard/rufus/wiki/FAQ)
