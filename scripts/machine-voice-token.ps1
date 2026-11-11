param([Parameter(Mandatory=$true)][string]$ManifestPath)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Machine voice token registration requires elevation.' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$roots = @(
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens',
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens'
)
$clsid = '{52586884-b3dc-46c5-a298-a49606cc5421}'
if ($manifest.Action -eq 'Add') {
    if (-not $manifest.Id.StartsWith('PocketTTS.Custom.') -or -not (Test-Path -LiteralPath $manifest.VoiceStatePath)) { throw 'Invalid Pocket TTS voice registration request.' }
    foreach ($property in @('VoicePromptSlowPath','VoicePromptNormalPath','VoicePromptFastPath')) {
        $promptPath = $manifest.$property
        if (-not $promptPath -or [IO.Path]::GetExtension($promptPath) -ine '.wav' -or -not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
            throw "Invalid prompt variant path: $property"
        }
    }
    foreach ($root in $roots) { if (Test-Path -LiteralPath (Join-Path $root $manifest.Id)) { throw 'A token with this ID already exists.' } }
    try {
        foreach ($root in $roots) {
            $key = Join-Path $root $manifest.Id
            New-Item -Path (Join-Path $key 'Attributes') -Force | Out-Null
            Set-Item -LiteralPath $key -Value $manifest.Name
            foreach ($entry in @{
                CLSID=$clsid
                VoiceName=$manifest.Id
                VoiceStatePath=$manifest.VoiceStatePath
                ModelLanguage=$manifest.ModelLanguage
                VoicePromptSlowPath=$manifest.VoicePromptSlowPath
                VoicePromptNormalPath=$manifest.VoicePromptNormalPath
                VoicePromptFastPath=$manifest.VoicePromptFastPath
                DisplayName=$manifest.Name
            }.GetEnumerator()) {
                New-ItemProperty -LiteralPath $key -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null
            }
            foreach ($entry in @{
                Name=$manifest.Name
                VoiceName=$manifest.Name
                Language='0409'
                Gender='Unknown'
                Age='Adult'
                Vendor='Pocket TTS'
                VoiceId=$manifest.Id
                VoiceStatePath=$manifest.VoiceStatePath
                ModelLanguage=$manifest.ModelLanguage
                VoicePromptSlowPath=$manifest.VoicePromptSlowPath
                VoicePromptNormalPath=$manifest.VoicePromptNormalPath
                VoicePromptFastPath=$manifest.VoicePromptFastPath
                Rate='1.0'
            }.GetEnumerator()) {
                New-ItemProperty -LiteralPath (Join-Path $key 'Attributes') -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null
            }
        }
    } catch {
        foreach ($root in $roots) {
            $key = Join-Path $root $manifest.Id
            if (Test-Path -LiteralPath $key) {
                $owner = (Get-ItemProperty -LiteralPath $key -Name CLSID -ErrorAction SilentlyContinue).CLSID
                if ($owner -eq $clsid) { Remove-Item -LiteralPath $key -Recurse -Force }
            }
        }
        throw
    }
} elseif ($manifest.Action -eq 'Remove') {
    if (-not $manifest.Id.StartsWith('PocketTTS.Custom.')) { throw 'Refusing to remove a token outside the Pocket TTS custom voice namespace.' }
    foreach ($root in $roots) {
        $key = Join-Path $root $manifest.Id
        if (Test-Path -LiteralPath $key) {
            $registered = (Get-ItemProperty -LiteralPath $key -Name CLSID -ErrorAction SilentlyContinue).CLSID
            if ($registered -ne $clsid) { throw 'Token is not registered to Pocket TTS.' }
        }
    }
    foreach ($root in $roots) {
        $key = Join-Path $root $manifest.Id
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    }
    foreach ($root in $roots) {
        if (Test-Path -LiteralPath (Join-Path $root $manifest.Id)) {
            throw "Pocket TTS voice token remains registered under $root."
        }
    }
} elseif ($manifest.Action -eq 'UpdateRatePrompts') {
    if (-not $manifest.Id.StartsWith('PocketTTS.Custom.')) { throw 'Refusing to update a token outside the Pocket TTS custom voice namespace.' }
    foreach ($property in @('VoicePromptSlowPath','VoicePromptNormalPath','VoicePromptFastPath')) {
        $promptPath = $manifest.$property
        if (-not $promptPath -or [IO.Path]::GetExtension($promptPath) -ine '.wav' -or -not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
            throw "Invalid prompt variant path: $property"
        }
    }
    foreach ($root in $roots) {
        $key = Join-Path $root $manifest.Id
        if (-not (Test-Path -LiteralPath $key)) { throw "Pocket TTS token is missing under $root." }
        $registered = (Get-ItemProperty -LiteralPath $key -Name CLSID -ErrorAction SilentlyContinue).CLSID
        if ($registered -ne $clsid) { throw "Token is not registered to Pocket TTS under $root." }
    }
    foreach ($root in $roots) {
        $key = Join-Path $root $manifest.Id
        foreach ($property in @('VoicePromptSlowPath','VoicePromptNormalPath','VoicePromptFastPath')) {
            New-ItemProperty -LiteralPath $key -Name $property -Value $manifest.$property -PropertyType String -Force | Out-Null
            New-ItemProperty -LiteralPath (Join-Path $key 'Attributes') -Name $property -Value $manifest.$property -PropertyType String -Force | Out-Null
        }
    }
} else { throw 'Unknown voice token operation.' }
