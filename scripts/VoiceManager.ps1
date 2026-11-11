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
$form.Size = New-Object Drawing.Size(620, 520)
$form.MinimumSize = New-Object Drawing.Size(620, 520)

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
$browse.Text = 'Browse…'
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

$create = New-Object Windows.Forms.Button
$create.Text = 'Create and register voice'
$create.Location = New-Object Drawing.Point(16, 405)
$create.Size = New-Object Drawing.Size(200, 34)
$form.Controls.Add($create)
$preview = New-Object Windows.Forms.Button
$preview.Text = 'Preview selected'
$preview.Location = New-Object Drawing.Point(230, 405)
$preview.Size = New-Object Drawing.Size(150, 34)
$form.Controls.Add($preview)
$remove = New-Object Windows.Forms.Button
$remove.Text = 'Remove selected'
$remove.Location = New-Object Drawing.Point(390, 405)
$remove.Size = New-Object Drawing.Size(100, 34)
$form.Controls.Add($remove)
$close = New-Object Windows.Forms.Button
$close.Text = 'Close'
$close.Location = New-Object Drawing.Point(500, 405)
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
        $status.Text = 'Creating the voice state… The first conversion may take a little while.'
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
    } catch {
        $status.Text = $_.Exception.Message
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Pocket TTS Voice Manager', 'OK', 'Error') | Out-Null
    }
})

$remove.Add_Click({
    $item = $voiceList.SelectedItem
    if (-not $item) { return }
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
[void]$form.ShowDialog()
