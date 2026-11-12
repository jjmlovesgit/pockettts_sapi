param(
    [string]$InstallRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$AddVoicePrompt,
    [string]$VoiceName,
    [string]$SetVoicePromptVariants,
    [string]$PromptAudio,
    [string]$RemoveVoiceToken,
    [switch]$ConfirmAuthorizedPrompt
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$clsid = '{52586884-b3dc-46c5-a298-a49606cc5421}'
$tokenRoot = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens'
$voicePrefix = 'PocketTTS.Custom.'
$tokenHelper = Join-Path $PSScriptRoot 'machine-voice-token.ps1'
$voiceDir = Join-Path $env:LOCALAPPDATA 'PocketTTS\Voices'
$maxVoiceStateBytes = 1900000
# The official local server caps the complete multipart request at 2 MiB.
# Keep each prompt below 1.8 MB to leave room for multipart framing.
$maxVoicePromptBytes = 1800000
$promptRateUtility = @(
    (Join-Path $InstallRoot 'tools\pocket_prompt_rate.exe'),
    (Join-Path $PSScriptRoot '..\build\sapi\prompt_rate.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$runtimeCandidates = @(
    (Join-Path $InstallRoot 'pocket-tts.exe'),
    (Join-Path $InstallRoot '.benchmark-cache\rust\unpacked\pocket-tts-3.3.0-x86_64-pc-windows-msvc\pocket-tts.exe')
)
$runtime = $runtimeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$modelCache = Join-Path $InstallRoot 'models\hf'
if (-not (Test-Path -LiteralPath $modelCache)) {
    $devCache = Join-Path $InstallRoot '.benchmark-cache\hf'
    if (Test-Path -LiteralPath $devCache) { $modelCache = $devCache }
}
$modelLanguage = 'english_7m_refl_2026-10'
try {
    $configuredLanguage = (Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\PocketTTS' -Name ModelLanguage -ErrorAction Stop).ModelLanguage
    if ($configuredLanguage -in @('english_2m_2026-10','english_7m_refl_2026-10')) { $modelLanguage = $configuredLanguage }
} catch {}

function Invoke-MachineVoiceToken([hashtable]$Request) {
    $manifestPath = Join-Path $env:TEMP ('PocketTTS-Voice-' + [guid]::NewGuid().ToString('N') + '.json')
    $Request | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $tokenHelper + '"'),'-ManifestPath',('"' + $manifestPath + '"'))
        if ($isAdmin) {
            & $powershell @arguments
            if ($LASTEXITCODE -ne 0) { throw "Machine voice token update failed ($LASTEXITCODE)." }
        } else {
            $process = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arguments -Wait -PassThru
            if ($process.ExitCode -ne 0) { throw "Machine voice token update failed ($($process.ExitCode))." }
        }
    } finally {
        Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
    }
}

function New-VoicePromptVariants([string]$SourcePath, [string]$Id) {
    if (-not $promptRateUtility) { throw 'Pocket TTS prompt-rate tool is missing. Repair the base installation.' }
    $slow = Join-Path $voiceDir ($Id + '-slow.wav')
    $normal = Join-Path $voiceDir ($Id + '-normal.wav')
    $fast = Join-Path $voiceDir ($Id + '-fast.wav')
    try {
        $null = & $promptRateUtility $SourcePath $slow '0.70'
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $slow)) { throw 'Could not create the slow pace prompt. Use an uncompressed 16-bit PCM WAV.' }
        $null = & $promptRateUtility $SourcePath $normal '1.00'
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $normal)) { throw 'Could not create the normal pace prompt. Use an uncompressed 16-bit PCM WAV.' }
        $null = & $promptRateUtility $SourcePath $fast '1.40'
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fast)) { throw 'Could not create the fast pace prompt. Use an uncompressed 16-bit PCM WAV.' }
        foreach ($path in @($slow,$normal,$fast)) {
            if ((Get-Item -LiteralPath $path).Length -gt $maxVoicePromptBytes) { throw 'This prompt is still too large for the local server after conversion to 24 kHz mono. Use a shorter WAV recording.' }
        }
        return @{Slow=$slow;Normal=$normal;Fast=$fast}
    } catch {
        foreach ($path in @($slow,$normal,$fast)) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function New-CachedRateStates([hashtable]$PromptPaths) {
    $env:HF_HUB_CACHE = $modelCache
    $env:HF_HUB_OFFLINE = '1'
    foreach ($pace in @('Slow','Fast')) {
        $path = [IO.Path]::ChangeExtension($PromptPaths[$pace], '.safetensors')
        $temp = $path + '.tmp'
        $excerpt = $path + '.excerpt.wav'
        try {
            & $runtime export-voice --quiet --language $modelLanguage $PromptPaths[$pace] $temp
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temp)) { throw "Could not cache the $pace voice pace." }
            if ((Get-Item -LiteralPath $temp).Length -gt $maxVoiceStateBytes) {
                Remove-Item -LiteralPath $temp -Force
                & $promptRateUtility $PromptPaths[$pace] $excerpt '1.00' '6.00'
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $excerpt)) { throw "Could not prepare a short $pace voice pace." }
                & $runtime export-voice --quiet --language $modelLanguage $excerpt $temp
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temp) -or
                    (Get-Item -LiteralPath $temp).Length -gt $maxVoiceStateBytes) {
                    throw "The $pace voice pace cannot fit the local server. Use a shorter source prompt."
                }
            }
            Move-Item -LiteralPath $temp -Destination $path -Force
        } finally {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $excerpt -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-CachedRateStates([hashtable]$PromptPaths) {
    foreach ($pace in @('Slow','Fast')) {
        if ($PromptPaths[$pace]) {
            $path = [IO.Path]::ChangeExtension($PromptPaths[$pace], '.safetensors')
            $full = [IO.Path]::GetFullPath($path)
            $root = [IO.Path]::GetFullPath($voiceDir).TrimEnd('\') + '\'
            if ($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

if ($AddVoicePrompt) {
    if (-not $ConfirmAuthorizedPrompt) { throw 'Pass -ConfirmAuthorizedPrompt after verifying you are authorized to use this voice.' }
    if (-not $runtime -or -not (Test-Path -LiteralPath $modelCache)) { throw 'Pocket TTS base runtime/model cache is missing.' }
    if (-not (Test-Path -LiteralPath $AddVoicePrompt -PathType Leaf)) { throw 'Prompt audio file does not exist.' }
    $source = Get-Item -LiteralPath $AddVoicePrompt
    if ($source.Extension -ne '.wav' -or $source.Length -gt 50MB) { throw 'Use a PCM WAV prompt smaller than 50 MB. MP3 and compressed WAV prompts are not supported for pace variants yet.' }
    if ([string]::IsNullOrWhiteSpace($VoiceName) -or $VoiceName.Trim().Length -gt 48) { throw 'VoiceName must contain 1 to 48 characters.' }
    $engineRegistered = (Test-Path -LiteralPath ('Registry::HKEY_CURRENT_USER\SOFTWARE\Classes\CLSID\' + $clsid)) -or
        (Test-Path -LiteralPath ('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\' + $clsid))
    if (-not $engineRegistered) { throw 'Pocket TTS SAPI engine is not registered.' }
    $env:HF_HUB_CACHE = $modelCache
    $env:HF_HUB_OFFLINE = '1'
    New-Item -ItemType Directory -Force -Path $voiceDir | Out-Null
    $slug = ($VoiceName.Trim() -replace '[^A-Za-z0-9_-]+','_').Trim('_')
    if (-not $slug) { $slug = 'Voice' }
    $id = $voicePrefix + $slug + '.' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $statePath = Join-Path $voiceDir ($id + '.safetensors')
    $tempPath = $statePath + '.tmp'
    $promptPaths = New-VoicePromptVariants $source.FullName $id
    & $runtime export-voice --language $modelLanguage $source.FullName $tempPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        foreach ($path in $promptPaths.Values) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        throw 'Pocket TTS could not create a voice state.'
    }
    Move-Item -LiteralPath $tempPath -Destination $statePath
    if ((Get-Item -LiteralPath $statePath).Length -gt $maxVoiceStateBytes) {
        Remove-Item -LiteralPath $statePath -Force
        foreach ($path in $promptPaths.Values) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        throw 'This prompt created a voice state larger than the shared server can accept. Use a shorter prompt (about 5 seconds) and create the voice again.'
    }
    try {
        New-CachedRateStates $promptPaths
        Invoke-MachineVoiceToken @{Action='Add';Id=$id;Name=$VoiceName.Trim();ModelLanguage=$modelLanguage;VoiceStatePath=$statePath;VoicePromptSlowPath=$promptPaths.Slow;VoicePromptNormalPath=$promptPaths.Normal;VoicePromptFastPath=$promptPaths.Fast}
    } catch {
        if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
        Remove-CachedRateStates $promptPaths
        foreach ($path in $promptPaths.Values) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        throw
    }
    Write-Output $id
    exit 0
}

if ($SetVoicePromptVariants) {
    if (-not $ConfirmAuthorizedPrompt) { throw 'Pass -ConfirmAuthorizedPrompt after verifying you are authorized to use this voice.' }
    if (-not $SetVoicePromptVariants.StartsWith($voicePrefix)) { throw 'Refusing to update a token outside the Pocket TTS custom voice namespace.' }
    if (-not $PromptAudio -or -not (Test-Path -LiteralPath $PromptAudio -PathType Leaf)) { throw 'Pass -PromptAudio with the original authorized PCM WAV used to create this voice.' }
    $key = Join-Path $tokenRoot $SetVoicePromptVariants
    if (-not (Test-Path -LiteralPath $key)) { throw 'Pocket TTS voice token does not exist.' }
    $registered = (Get-ItemProperty -LiteralPath $key -Name CLSID -ErrorAction SilentlyContinue).CLSID
    if ($registered -ne $clsid) { throw 'Token is not registered to the Pocket TTS SAPI engine.' }
    $statePath = (Get-ItemProperty -LiteralPath $key -Name VoiceStatePath -ErrorAction SilentlyContinue).VoiceStatePath
    $voiceDirFull = [IO.Path]::GetFullPath($voiceDir).TrimEnd('\') + '\'
    if (-not $statePath -or -not [IO.Path]::GetFullPath($statePath).StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'This voice state belongs to another Windows profile and cannot be updated here.'
    }
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'The cloned voice state is missing; repair or recreate this voice first.' }
    $source = Get-Item -LiteralPath $PromptAudio
    if ($source.Extension -ine '.wav' -or $source.Length -gt 50MB) { throw 'Use the original uncompressed PCM WAV prompt smaller than 50 MB.' }
    New-Item -ItemType Directory -Force -Path $voiceDir | Out-Null
    $oldPromptPaths = @{}
    foreach ($pace in @('Slow','Normal','Fast')) {
        $oldPromptPaths[$pace] = (Get-ItemProperty -LiteralPath $key -Name ("VoicePrompt${pace}Path") -ErrorAction SilentlyContinue).("VoicePrompt${pace}Path")
    }
    $stagedId = $SetVoicePromptVariants + '.rate.' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $promptPaths = New-VoicePromptVariants $source.FullName $stagedId
    try {
        New-CachedRateStates $promptPaths
        Invoke-MachineVoiceToken @{Action='UpdateRatePrompts';Id=$SetVoicePromptVariants;VoicePromptSlowPath=$promptPaths.Slow;VoicePromptNormalPath=$promptPaths.Normal;VoicePromptFastPath=$promptPaths.Fast}
        Remove-CachedRateStates $oldPromptPaths
        foreach ($path in $oldPromptPaths.Values) {
            if ($path -and [IO.Path]::GetFullPath($path).StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Remove-CachedRateStates $promptPaths
        foreach ($path in $promptPaths.Values) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        throw
    }
    Write-Output "Updated rate prompts for $SetVoicePromptVariants"
    exit 0
}

if ($RemoveVoiceToken) {
    if (-not $RemoveVoiceToken.StartsWith($voicePrefix)) { throw 'Refusing to remove a token outside the Pocket TTS custom voice namespace.' }
    $key = Join-Path $tokenRoot $RemoveVoiceToken
    if (-not (Test-Path -LiteralPath $key)) { throw 'Pocket TTS voice token does not exist.' }
    $registered = (Get-ItemProperty -LiteralPath $key -Name CLSID -ErrorAction SilentlyContinue).CLSID
    if ($registered -ne $clsid) { throw 'Token is not registered to the Pocket TTS SAPI engine.' }
    $statePath = (Get-ItemProperty -LiteralPath $key -Name VoiceStatePath -ErrorAction SilentlyContinue).VoiceStatePath
    $promptPaths = @(
        (Get-ItemProperty -LiteralPath $key -Name VoicePromptSlowPath -ErrorAction SilentlyContinue).VoicePromptSlowPath,
        (Get-ItemProperty -LiteralPath $key -Name VoicePromptNormalPath -ErrorAction SilentlyContinue).VoicePromptNormalPath,
        (Get-ItemProperty -LiteralPath $key -Name VoicePromptFastPath -ErrorAction SilentlyContinue).VoicePromptFastPath
    )
    $voiceDirFull = [IO.Path]::GetFullPath($voiceDir).TrimEnd('\') + '\'
    if (-not $statePath -or -not [IO.Path]::GetFullPath($statePath).StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'This voice state belongs to another Windows profile and cannot be removed here.'
    }
    Invoke-MachineVoiceToken @{Action='Remove';Id=$RemoveVoiceToken}
    if ($statePath) {
        $stateFull = [IO.Path]::GetFullPath($statePath)
        if ($stateFull.StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $stateFull)) { Remove-Item -LiteralPath $stateFull -Force }
    }
    $voiceDirFull = [IO.Path]::GetFullPath($voiceDir).TrimEnd('\') + '\'
    foreach ($path in $promptPaths) {
        if ($path) {
            $full = [IO.Path]::GetFullPath($path)
            if ($full.StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase)) {
                if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force }
                $cached = [IO.Path]::ChangeExtension($full, '.safetensors')
                if (Test-Path -LiteralPath $cached) { Remove-Item -LiteralPath $cached -Force }
            }
        }
    }
    Write-Output "Removed $RemoveVoiceToken"
    exit 0
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Pocket TTS Voice Manager'
$iconPath = Join-Path $InstallRoot 'pockettts-pocket.ico'
if (Test-Path -LiteralPath $iconPath) { $form.Icon = [Drawing.Icon]::new($iconPath) }
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size(620, 650)
$form.MinimumSize = New-Object Drawing.Size(620, 650)

$voicesLabel = New-Object Windows.Forms.Label
$voicesLabel.Text = 'Installed custom voices'
$voicesLabel.Location = New-Object Drawing.Point(16, 14)
$voicesLabel.AutoSize = $true
$form.Controls.Add($voicesLabel)

$voiceList = New-Object Windows.Forms.ListBox
$voiceList.Location = New-Object Drawing.Point(16, 38)
$voiceList.Size = New-Object Drawing.Size(570, 130)
$voiceList.DisplayMember = 'Name'
$form.Controls.Add($voiceList)

$nameLabel = New-Object Windows.Forms.Label
$nameLabel.Text = 'Voice name'
$nameLabel.Location = New-Object Drawing.Point(16, 183)
$nameLabel.AutoSize = $true
$form.Controls.Add($nameLabel)
$nameBox = New-Object Windows.Forms.TextBox
$nameBox.Location = New-Object Drawing.Point(110, 180)
$nameBox.Size = New-Object Drawing.Size(476, 24)
$form.Controls.Add($nameBox)

$audioLabel = New-Object Windows.Forms.Label
$audioLabel.Text = 'Prompt audio'
$audioLabel.Location = New-Object Drawing.Point(16, 218)
$audioLabel.AutoSize = $true
$form.Controls.Add($audioLabel)
$audioBox = New-Object Windows.Forms.TextBox
$audioBox.Location = New-Object Drawing.Point(110, 215)
$audioBox.Size = New-Object Drawing.Size(380, 24)
$form.Controls.Add($audioBox)
$browse = New-Object Windows.Forms.Button
$browse.Text = 'Browse...'
$browse.Location = New-Object Drawing.Point(500, 213)
$browse.Size = New-Object Drawing.Size(86, 28)
$form.Controls.Add($browse)

$consent = New-Object Windows.Forms.CheckBox
$consent.Text = 'I am authorized to use this voice and will not use it to deceive or impersonate others.'
$consent.Location = New-Object Drawing.Point(16, 255)
$consent.Size = New-Object Drawing.Size(570, 42)
$form.Controls.Add($consent)

$status = New-Object Windows.Forms.Label
$status.Text = 'Cloning keeps slow, normal, and fast prompt variants. SAPI speed selects one of these three pace settings.'
$status.Location = New-Object Drawing.Point(16, 308)
$status.Size = New-Object Drawing.Size(570, 42)
$form.Controls.Add($status)

$previewLabel = New-Object Windows.Forms.Label
$previewLabel.Text = 'Preview text'
$previewLabel.Location = New-Object Drawing.Point(16, 355)
$previewLabel.AutoSize = $true
$form.Controls.Add($previewLabel)
$previewBox = New-Object Windows.Forms.TextBox
$previewBox.Text = 'This is a preview of your Pocket TTS voice.'
$previewBox.Location = New-Object Drawing.Point(110, 352)
$previewBox.Size = New-Object Drawing.Size(476, 24)
$form.Controls.Add($previewBox)

$defaultGroup = New-Object Windows.Forms.GroupBox
$defaultGroup.Text = 'Windows app defaults (OneCore and classic SAPI)'
$defaultGroup.Location = New-Object Drawing.Point(16, 390)
$defaultGroup.Size = New-Object Drawing.Size(570, 122)
$form.Controls.Add($defaultGroup)

$defaultVoiceLabel = New-Object Windows.Forms.Label
$defaultVoiceLabel.Text = 'Voice'
$defaultVoiceLabel.Location = New-Object Drawing.Point(12, 25)
$defaultVoiceLabel.AutoSize = $true
$defaultGroup.Controls.Add($defaultVoiceLabel)
$defaultVoiceList = New-Object Windows.Forms.ComboBox
$defaultVoiceList.Location = New-Object Drawing.Point(90, 21)
$defaultVoiceList.Size = New-Object Drawing.Size(462, 24)
$defaultVoiceList.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
$defaultVoiceList.DisplayMember = 'Name'
$defaultGroup.Controls.Add($defaultVoiceList)

$defaultStatus = New-Object Windows.Forms.Label
$defaultStatus.Text = ''
$defaultStatus.Location = New-Object Drawing.Point(12, 51)
$defaultStatus.Size = New-Object Drawing.Size(540, 24)
$defaultGroup.Controls.Add($defaultStatus)

$setDefault = New-Object Windows.Forms.Button
$setDefault.Text = 'Set as default'
$setDefault.Location = New-Object Drawing.Point(190, 79)
$setDefault.Size = New-Object Drawing.Size(170, 30)
$defaultGroup.Controls.Add($setDefault)
$restoreDefault = New-Object Windows.Forms.Button
$restoreDefault.Text = 'Restore previous'
$restoreDefault.Location = New-Object Drawing.Point(370, 79)
$restoreDefault.Size = New-Object Drawing.Size(170, 30)
$defaultGroup.Controls.Add($restoreDefault)
$previewDefault = New-Object Windows.Forms.Button
$previewDefault.Text = 'Preview choice'
$previewDefault.Location = New-Object Drawing.Point(10, 79)
$previewDefault.Size = New-Object Drawing.Size(170, 30)
$defaultGroup.Controls.Add($previewDefault)

$create = New-Object Windows.Forms.Button
$create.Text = 'Create and register voice'
$create.Location = New-Object Drawing.Point(16, 530)
$create.Size = New-Object Drawing.Size(200, 34)
$form.Controls.Add($create)
$preview = New-Object Windows.Forms.Button
$preview.Text = 'Preview selected clone'
$preview.Location = New-Object Drawing.Point(230, 530)
$preview.Size = New-Object Drawing.Size(150, 34)
$form.Controls.Add($preview)
$remove = New-Object Windows.Forms.Button
$remove.Text = 'Remove selected'
$remove.Location = New-Object Drawing.Point(390, 530)
$remove.Size = New-Object Drawing.Size(100, 34)
$form.Controls.Add($remove)
$close = New-Object Windows.Forms.Button
$close.Text = 'Close'
$close.Location = New-Object Drawing.Point(500, 530)
$close.Size = New-Object Drawing.Size(86, 34)
$form.Controls.Add($close)

function Refresh-VoiceList {
    $voiceList.Items.Clear()
    if (-not (Test-Path -LiteralPath $tokenRoot)) { return }
    $voiceDirFull = [IO.Path]::GetFullPath($voiceDir).TrimEnd('\') + '\'
    Get-ChildItem -LiteralPath $tokenRoot | Where-Object { $_.PSChildName.StartsWith($voicePrefix) } | ForEach-Object {
        $voiceState = (Get-ItemProperty -LiteralPath $_.PSPath -Name VoiceStatePath -ErrorAction SilentlyContinue).VoiceStatePath
        if (-not $voiceState -or -not [IO.Path]::GetFullPath($voiceState).StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase)) { return }
        $label = (Get-ItemProperty -LiteralPath $_.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
        if (-not $label) { $label = $_.PSChildName.Substring($voicePrefix.Length) }
        [void]$voiceList.Items.Add([pscustomobject]@{ Name=$label; Path=$_.PSPath; Id=$_.PSChildName })
    }
}

$oneCoreTokenRoots = @(
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens',
    'Registry::HKEY_CURRENT_USER\Software\Microsoft\Speech_OneCore\Voices\Tokens'
)
$oneCoreDefaultKey = 'HKCU:\Software\Microsoft\Speech_OneCore\Voices'
$classicDefaultKey = 'HKCU:\Software\Microsoft\Speech\Voices'
$classicTokenRoots = @(
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens',
    'Registry::HKEY_CURRENT_USER\Software\Microsoft\Speech\Voices\Tokens'
)
$defaultBackupKey = 'HKCU:\Software\PocketTTS\VoiceManager'

function Get-ClassicVoiceTokenPath([string]$OneCoreTokenPath) {
    $tokenId = $OneCoreTokenPath.Split('\')[-1]
    foreach ($root in $classicTokenRoots) {
        $key = Join-Path $root $tokenId
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $hive = if ($root -match 'HKEY_LOCAL_MACHINE') { 'HKEY_LOCAL_MACHINE' } else { 'HKEY_CURRENT_USER' }
        $relativeRoot = $root -replace '^Registry::HKEY_(LOCAL_MACHINE|CURRENT_USER)\\', ''
        return $hive + '\' + $relativeRoot + '\' + $tokenId
    }
    return $null
}

function Refresh-OneCoreVoiceList {
    $defaultVoiceList.Items.Clear()
    foreach ($root in $oneCoreTokenRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hive = if ($root -match 'HKEY_LOCAL_MACHINE') { 'HKEY_LOCAL_MACHINE' } else { 'HKEY_CURRENT_USER' }
        $relativeRoot = $root -replace '^Registry::HKEY_(LOCAL_MACHINE|CURRENT_USER)\\', ''
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $tokenPath = $hive + '\' + $relativeRoot + '\' + $key.PSChildName
            $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $name = $properties.DisplayName
            if (-not $name) { $name = $key.GetValue('') }
            if (-not $name) {
                $attributes = Join-Path $key.PSPath 'Attributes'
                $name = (Get-ItemProperty -LiteralPath $attributes -Name Name -ErrorAction SilentlyContinue).Name
            }
            if (-not $name) { $name = $key.PSChildName }
            [void]$defaultVoiceList.Items.Add([pscustomobject]@{Name=[string]$name;TokenPath=$tokenPath})
        }
    }
    $current = (Get-ItemProperty -LiteralPath $oneCoreDefaultKey -Name DefaultTokenId -ErrorAction SilentlyContinue).DefaultTokenId
    $selectedIndex = -1
    $currentVoice = $null
    for ($index = 0; $index -lt $defaultVoiceList.Items.Count; $index++) {
        $voice = $defaultVoiceList.Items[$index]
        if ($voice.TokenPath -eq $current) { $selectedIndex = $index; $currentVoice = $voice.Name; break }
    }
    if ($selectedIndex -ge 0) { $defaultVoiceList.SelectedIndex = $selectedIndex }
    $classicCurrent = (Get-ItemProperty -LiteralPath $classicDefaultKey -Name DefaultTokenId -ErrorAction SilentlyContinue).DefaultTokenId
    $classicVoice = $null
    if ($classicCurrent) {
        foreach ($root in $classicTokenRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
                $hive = if ($root -match 'HKEY_LOCAL_MACHINE') { 'HKEY_LOCAL_MACHINE' } else { 'HKEY_CURRENT_USER' }
                $relativeRoot = $root -replace '^Registry::HKEY_(LOCAL_MACHINE|CURRENT_USER)\\', ''
                if (($hive + '\' + $relativeRoot + '\' + $key.PSChildName) -eq $classicCurrent) {
                    $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
                    $classicVoice = $properties.DisplayName
                    if (-not $classicVoice) { $classicVoice = $key.GetValue('') }
                    if (-not $classicVoice) { $classicVoice = $key.PSChildName }
                    break
                }
            }
            if ($classicVoice) { break }
        }
    }
    if (-not $currentVoice -and $current) { $currentVoice = 'unlisted OneCore voice' }
    if (-not $classicVoice -and $classicCurrent) { $classicVoice = 'unlisted SAPI voice' }
    if ($currentVoice -or $classicVoice) { $defaultStatus.Text = "Current: OneCore $currentVoice; SAPI $classicVoice" }
    else { $defaultStatus.Text = 'Windows has no saved per-user voice defaults.' }
    $backup = Get-ItemProperty -LiteralPath $defaultBackupKey -ErrorAction SilentlyContinue
    $restoreDefault.Enabled = ($null -ne $backup -and (
        $backup.PSObject.Properties.Name -contains 'PreviousOneCoreDefaultTokenId' -or
        $backup.PSObject.Properties.Name -contains 'PreviousClassicDefaultTokenId' -or
        $backup.PSObject.Properties.Name -contains 'PreviousDefaultTokenId'
    ))
}

$setDefault.Add_Click({
    try {
        $selected = $defaultVoiceList.SelectedItem
        if (-not $selected) { throw 'Select a registered Windows OneCore voice first.' }
        $tokenHivePath = 'Registry::' + $selected.TokenPath
        if (-not (Test-Path -LiteralPath $tokenHivePath)) { throw 'That voice token is no longer registered. Reopen Voice Manager to refresh the list.' }
        New-Item -Path $oneCoreDefaultKey -Force | Out-Null
        New-Item -Path $classicDefaultKey -Force | Out-Null
        New-Item -Path $defaultBackupKey -Force | Out-Null
        $oneCoreCurrent = (Get-ItemProperty -LiteralPath $oneCoreDefaultKey -Name DefaultTokenId -ErrorAction SilentlyContinue).DefaultTokenId
        $classicCurrent = (Get-ItemProperty -LiteralPath $classicDefaultKey -Name DefaultTokenId -ErrorAction SilentlyContinue).DefaultTokenId
        $classicSelected = Get-ClassicVoiceTokenPath $selected.TokenPath
        $shouldSetOneCore = ($oneCoreCurrent -ne $selected.TokenPath)
        $shouldSetClassic = ($classicSelected -and $classicCurrent -ne $classicSelected)
        if ($shouldSetOneCore -or $shouldSetClassic) {
            $existingBackup = Get-ItemProperty -LiteralPath $defaultBackupKey -ErrorAction SilentlyContinue
            $previousOneCoreToSave = [string]$oneCoreCurrent
            $previousOneCoreWasSetToSave = [bool]$oneCoreCurrent
            if ($existingBackup -and
                $existingBackup.PSObject.Properties.Name -notcontains 'PreviousOneCoreDefaultTokenId' -and
                $existingBackup.PSObject.Properties.Name -contains 'PreviousDefaultTokenId') {
                $previousOneCoreToSave = [string]$existingBackup.PreviousDefaultTokenId
                $previousOneCoreWasSetToSave = [bool]$existingBackup.PreviousDefaultWasSet
            }
            New-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousOneCoreDefaultTokenId -Value $previousOneCoreToSave -PropertyType String -Force | Out-Null
            New-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousOneCoreDefaultWasSet -Value ([int]$previousOneCoreWasSetToSave) -PropertyType DWord -Force | Out-Null
            New-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousClassicDefaultTokenId -Value ([string]$classicCurrent) -PropertyType String -Force | Out-Null
            New-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousClassicDefaultWasSet -Value ([int][bool]$classicCurrent) -PropertyType DWord -Force | Out-Null
        }
        if ($shouldSetOneCore) {
            Set-ItemProperty -LiteralPath $oneCoreDefaultKey -Name DefaultTokenId -Value $selected.TokenPath -Type String
        }
        if ($shouldSetClassic) {
            Set-ItemProperty -LiteralPath $classicDefaultKey -Name DefaultTokenId -Value $classicSelected -Type String
        }
        Refresh-OneCoreVoiceList
        if ($classicSelected) { $defaultStatus.Text = "Set $($selected.Name) as this user's SAPI and OneCore defaults. Restart the target app." }
        else { $defaultStatus.Text = "Set $($selected.Name) as this user's OneCore default; no matching SAPI token was found." }
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Pocket TTS Voice Manager', 'OK', 'Error') | Out-Null
    }
})

$restoreDefault.Add_Click({
    try {
        $backup = Get-ItemProperty -LiteralPath $defaultBackupKey -ErrorAction Stop
        $hasOneCoreBackup = $backup.PSObject.Properties.Name -contains 'PreviousOneCoreDefaultTokenId'
        $hasClassicBackup = $backup.PSObject.Properties.Name -contains 'PreviousClassicDefaultTokenId'
        $hasLegacyBackup = $backup.PSObject.Properties.Name -contains 'PreviousDefaultTokenId'
        if (-not ($hasOneCoreBackup -or $hasClassicBackup -or $hasLegacyBackup)) { throw 'No previous speech defaults have been saved yet.' }
        $restoreOneCore = $hasOneCoreBackup -or $hasLegacyBackup
        $restoreClassic = $hasClassicBackup
        $previousOneCore = $null
        $previousOneCoreWasSet = $false
        $previousClassic = $null
        $previousClassicWasSet = $false
        if ($hasOneCoreBackup -or $hasLegacyBackup) {
            $previousOneCore = if ($hasOneCoreBackup) { [string]$backup.PreviousOneCoreDefaultTokenId } else { [string]$backup.PreviousDefaultTokenId }
            $previousOneCoreWasSet = if ($hasOneCoreBackup) { [bool]$backup.PreviousOneCoreDefaultWasSet } else { [bool]$backup.PreviousDefaultWasSet }
            if ($previousOneCoreWasSet -and (-not $previousOneCore -or -not (Test-Path -LiteralPath ('Registry::' + $previousOneCore)))) {
                throw 'The saved previous OneCore voice is no longer installed, so it cannot be restored.'
            }
        }
        if ($hasClassicBackup) {
            $previousClassic = [string]$backup.PreviousClassicDefaultTokenId
            $previousClassicWasSet = [bool]$backup.PreviousClassicDefaultWasSet
            if ($previousClassicWasSet -and (-not $previousClassic -or -not (Test-Path -LiteralPath ('Registry::' + $previousClassic)))) {
                throw 'The saved previous SAPI voice is no longer installed, so it cannot be restored.'
            }
        }
        New-Item -Path $oneCoreDefaultKey -Force | Out-Null
        New-Item -Path $classicDefaultKey -Force | Out-Null
        if ($restoreOneCore) {
            if ($previousOneCoreWasSet) { Set-ItemProperty -LiteralPath $oneCoreDefaultKey -Name DefaultTokenId -Value $previousOneCore -Type String }
            else { Remove-ItemProperty -LiteralPath $oneCoreDefaultKey -Name DefaultTokenId -ErrorAction SilentlyContinue }
        }
        if ($restoreClassic) {
            if ($previousClassicWasSet) { Set-ItemProperty -LiteralPath $classicDefaultKey -Name DefaultTokenId -Value $previousClassic -Type String }
            else { Remove-ItemProperty -LiteralPath $classicDefaultKey -Name DefaultTokenId -ErrorAction SilentlyContinue }
        }
        Remove-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousDefaultTokenId -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousDefaultWasSet -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousOneCoreDefaultTokenId -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousOneCoreDefaultWasSet -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousClassicDefaultTokenId -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $defaultBackupKey -Name PreviousClassicDefaultWasSet -ErrorAction SilentlyContinue
        Refresh-OneCoreVoiceList
        $defaultStatus.Text = 'Restored the previous SAPI and OneCore defaults. Restart target apps.'
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Pocket TTS Voice Manager', 'OK', 'Error') | Out-Null
    }
})

$previewDefault.Add_Click({
    $speaker = $null
    $token = $null
    try {
        $selected = $defaultVoiceList.SelectedItem
        if (-not $selected) { throw 'Choose a voice in the OneCore dropdown first.' }
        if (-not $previewBox.Text.Trim()) { throw 'Enter preview text first.' }
        $tokenPath = 'Registry::' + $selected.TokenPath
        if (-not (Test-Path -LiteralPath $tokenPath)) { throw 'That voice is no longer registered. Reopen Voice Manager to refresh the list.' }
        $tokenId = $selected.TokenPath.Split('\')[-1]
        $classicTokenPath = Join-Path $tokenRoot $tokenId
        $previewTokenId = if (Test-Path -LiteralPath $classicTokenPath) {
            'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\' + $tokenId
        } else { $selected.TokenPath }
        $token = New-Object -ComObject SAPI.SpObjectToken
        $token.SetId($previewTokenId, '', $false)
        $speaker = New-Object -ComObject SAPI.SpVoice
        $speaker.Voice = $token
        [void]$speaker.Speak($previewBox.Text.Trim())
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Pocket TTS Voice Manager', 'OK', 'Error') | Out-Null
    } finally {
        if ($speaker) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($speaker) }
        if ($token) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($token) }
    }
})

$browse.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = 'PCM WAV prompts (*.wav)|*.wav|All files (*.*)|*.*'
    $dialog.Title = 'Choose an authorized voice prompt'
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $audioBox.Text = $dialog.FileName }
    $dialog.Dispose()
})

$create.Add_Click({
    try {
        if (-not $runtime) { throw 'Pocket TTS base runtime is missing. Install the Pocket TTS base package first.' }
        $engineRegistered = (Test-Path -LiteralPath ('Registry::HKEY_CURRENT_USER\SOFTWARE\Classes\CLSID\' + $clsid)) -or
            (Test-Path -LiteralPath ('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\' + $clsid))
        if (-not $engineRegistered) {
            throw 'Pocket TTS SAPI engine is not registered. Repair the base installation first.'
        }
        if (-not $consent.Checked) { throw 'Confirm that you are authorized to use this voice.' }
        $name = $nameBox.Text.Trim()
        if ($name.Length -lt 1 -or $name.Length -gt 48) { throw 'Voice name must be between 1 and 48 characters.' }
        $source = $audioBox.Text.Trim()
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Choose an existing PCM WAV prompt.' }
        $audio = Get-Item -LiteralPath $source
        if ($audio.Extension -ne '.wav' -or $audio.Length -gt 50MB) { throw 'Use a PCM WAV prompt smaller than 50 MB. MP3 and compressed WAV prompts are not supported for pace variants yet.' }
        if (-not (Test-Path -LiteralPath $modelCache)) { throw 'The offline model cache is missing. Repair the base installation first.' }
        New-Item -ItemType Directory -Force -Path $voiceDir | Out-Null
        $slug = ($name -replace '[^A-Za-z0-9_-]+','_').Trim('_')
        if (-not $slug) { $slug = 'Voice' }
        $id = $voicePrefix + $slug + '.' + [guid]::NewGuid().ToString('N').Substring(0,8)
        $statePath = Join-Path $voiceDir ($id + '.safetensors')
        $tempPath = $statePath + '.tmp'
        $promptPaths = New-VoicePromptVariants $source $id
        $status.Text = 'Creating the voice state... The first conversion may take a little while.'
        $form.Refresh()
        $env:HF_HUB_CACHE = $modelCache
        $env:HF_HUB_OFFLINE = '1'
        & $runtime export-voice --language $modelLanguage $source $tempPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            foreach ($path in $promptPaths.Values) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
            throw 'Pocket TTS could not create a voice state.'
        }
        Move-Item -LiteralPath $tempPath -Destination $statePath
        if ((Get-Item -LiteralPath $statePath).Length -gt $maxVoiceStateBytes) {
            Remove-Item -LiteralPath $statePath -Force
            foreach ($path in $promptPaths.Values) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
            throw 'This prompt created a voice state larger than the shared server can accept. Use a shorter prompt (about 5 seconds) and create the voice again.'
        }
        try {
            New-CachedRateStates $promptPaths
            Invoke-MachineVoiceToken @{Action='Add';Id=$id;Name=$name;ModelLanguage=$modelLanguage;VoiceStatePath=$statePath;VoicePromptSlowPath=$promptPaths.Slow;VoicePromptNormalPath=$promptPaths.Normal;VoicePromptFastPath=$promptPaths.Fast}
        } catch {
            if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
            Remove-CachedRateStates $promptPaths
            foreach ($path in $promptPaths.Values) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
            throw
        }
        $status.Text = 'Voice created and registered for Windows apps.'
        Refresh-VoiceList
        Refresh-OneCoreVoiceList
    } catch {
        $status.Text = $_.Exception.Message
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Pocket TTS Voice Manager', 'OK', 'Error') | Out-Null
    }
})

$remove.Add_Click({
    $item = $voiceList.SelectedItem
    if (-not $item) { return }
    $currentOneCoreDefault = (Get-ItemProperty -LiteralPath $oneCoreDefaultKey -Name DefaultTokenId -ErrorAction SilentlyContinue).DefaultTokenId
    $currentClassicDefault = (Get-ItemProperty -LiteralPath $classicDefaultKey -Name DefaultTokenId -ErrorAction SilentlyContinue).DefaultTokenId
    $oneCoreVoicePath = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\' + $item.Id
    $classicVoicePath = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\' + $item.Id
    if ($currentOneCoreDefault -eq $oneCoreVoicePath -or $currentClassicDefault -eq $classicVoicePath) {
        [Windows.Forms.MessageBox]::Show('This voice is a current Windows default. Select a different default voice above, then remove it.', 'Pocket TTS Voice Manager', 'OK', 'Information') | Out-Null
        return
    }
    $key = Join-Path $tokenRoot $item.Id
    $registered = (Get-ItemProperty -LiteralPath $key -Name CLSID -ErrorAction SilentlyContinue).CLSID
    if ($registered -ne $clsid) {
        [Windows.Forms.MessageBox]::Show('This token does not belong to Pocket TTS. It was left untouched.', 'Pocket TTS Voice Manager') | Out-Null
        return
    }
    $path = (Get-ItemProperty -LiteralPath $key -Name VoiceStatePath -ErrorAction SilentlyContinue).VoiceStatePath
    $promptPaths = @(
        (Get-ItemProperty -LiteralPath $key -Name VoicePromptSlowPath -ErrorAction SilentlyContinue).VoicePromptSlowPath,
        (Get-ItemProperty -LiteralPath $key -Name VoicePromptNormalPath -ErrorAction SilentlyContinue).VoicePromptNormalPath,
        (Get-ItemProperty -LiteralPath $key -Name VoicePromptFastPath -ErrorAction SilentlyContinue).VoicePromptFastPath
    )
    $voiceDirFull = [IO.Path]::GetFullPath($voiceDir).TrimEnd('\') + '\'
    if (-not $path -or -not [IO.Path]::GetFullPath($path).StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase)) {
        [Windows.Forms.MessageBox]::Show('This voice belongs to another Windows profile and was left untouched.', 'Pocket TTS Voice Manager') | Out-Null
        return
    }
    try { Invoke-MachineVoiceToken @{Action='Remove';Id=$item.Id} }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Pocket TTS Voice Manager', 'OK', 'Error') | Out-Null; return }
    if ($path) {
        $pathFull = [IO.Path]::GetFullPath($path)
        if ($pathFull.StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $pathFull)) {
            Remove-Item -LiteralPath $pathFull -Force
        } elseif (-not $pathFull.StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase)) {
            $status.Text = 'Token removed; its external voice-state file was left untouched.'
        }
    }
    foreach ($promptPath in $promptPaths) {
        if ($promptPath) {
            $promptFull = [IO.Path]::GetFullPath($promptPath)
            if ($promptFull.StartsWith($voiceDirFull,[StringComparison]::OrdinalIgnoreCase)) {
                if (Test-Path -LiteralPath $promptFull) { Remove-Item -LiteralPath $promptFull -Force }
                $cached = [IO.Path]::ChangeExtension($promptFull, '.safetensors')
                if (Test-Path -LiteralPath $cached) { Remove-Item -LiteralPath $cached -Force }
            }
        }
    }
    Refresh-VoiceList
    Refresh-OneCoreVoiceList
    $status.Text = 'Removed from SAPI and OneCore. Restart speech apps to refresh their voice lists.'
})

$preview.Add_Click({
    $speaker = $null
    $token = $null
    try {
        $item = $voiceList.SelectedItem
        if (-not $item) { throw 'Select a Pocket TTS voice first.' }
        if (-not $previewBox.Text.Trim()) { throw 'Enter preview text first.' }
        $voiceStatePath = (Get-ItemProperty -LiteralPath (Join-Path $tokenRoot $item.Id) -Name VoiceStatePath -ErrorAction Stop).VoiceStatePath
        $voiceState = Get-Item -LiteralPath $voiceStatePath -ErrorAction Stop
        if ($voiceState.Length -gt $maxVoiceStateBytes) {
            throw 'This voice state is too large for the shared Pocket TTS server. Recreate it from a shorter prompt (about 5 seconds), then remove this oversized voice.'
        }
        $token = New-Object -ComObject SAPI.SpObjectToken
        $token.SetId('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\' + $item.Id, '', $false)
        $speaker = New-Object -ComObject SAPI.SpVoice
        $speaker.Voice = $token
        [void]$speaker.Speak($previewBox.Text.Trim())
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Pocket TTS Voice Manager', 'OK', 'Error') | Out-Null
    } finally {
        if ($speaker) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($speaker) }
        if ($token) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($token) }
    }
})

$close.Add_Click({ $form.Close() })
Refresh-VoiceList
Refresh-OneCoreVoiceList
[void]$form.ShowDialog()
