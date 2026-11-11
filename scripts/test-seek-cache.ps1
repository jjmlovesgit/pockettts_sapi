$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dll = Join-Path $root 'build\sapi\pocket_sapi_seek_test.dll'
$clsid = '{2f28f1b0-0e38-49e7-9f14-0ccb3c11c709}'
$comKey = "Registry::HKEY_CURRENT_USER\SOFTWARE\Classes\CLSID\$clsid"
$tokenKey = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Speech\Voices\Tokens\PocketTTSProof7m'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Build the test CLSID DLL first.' }
if ((Test-Path -LiteralPath $comKey) -or (Test-Path -LiteralPath $tokenKey)) {
    throw 'Temporary test registration already exists; inspect it before continuing.'
}

$results = @()
try {
    $inproc = New-Item -Path (Join-Path $comKey 'InprocServer32') -Force
    Set-Item -LiteralPath $inproc.PSPath -Value $dll
    New-ItemProperty -LiteralPath $inproc.PSPath -Name ThreadingModel -Value Both -PropertyType String -Force | Out-Null
    New-Item -Path (Join-Path $tokenKey 'Attributes') -Force | Out-Null
    Set-Item -LiteralPath $tokenKey -Value 'Pocket TTS seek cache test'
    New-ItemProperty -LiteralPath $tokenKey -Name CLSID -Value $clsid -PropertyType String -Force | Out-Null
    foreach ($entry in @{Name='Pocket TTS seek cache test';Gender='Male';Age='Adult'}.GetEnumerator()) {
        New-ItemProperty -LiteralPath (Join-Path $tokenKey 'Attributes') -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null
    }

    foreach ($case in @(
        @{Language='english_7m_refl_2026-10'; Voice='Alba.safetensors'; Locale='409'; Text='The next sentence should play immediately when I return to it.'},
        @{Language='french'; Voice='estelle-french.safetensors'; Locale='40c'; Text='Bonjour, je retourne à cette phrase pour vérifier la lecture.'},
        @{Language='german'; Voice='juergen-german.safetensors'; Locale='407'; Text='Nachmittags treffe ich oft meine Freunde in einem kleinen Café, oder ich gehe im Park spazieren.'},
        @{Language='italian'; Voice='giovanni-italian.safetensors'; Locale='410'; Text='Buongiorno, torno a questa frase per controllare la lettura.'},
        @{Language='spanish'; Voice='lola-spanish.safetensors'; Locale='40a'; Text='Buenos días, vuelvo a esta frase para comprobar la lectura.'},
        @{Language='portuguese'; Voice='rafael-portuguese.safetensors'; Locale='416'; Text='Bom dia, volto a esta frase para verificar a leitura.'},
        @{Language='dutch'; Voice='daan-dutch.safetensors'; Locale='413'; Text='Elke ochtend drink ik een kop koffie. Daarna ga ik naar mijn werk en ontmoet ik mijn vrienden.'}
    )) {
        Set-ItemProperty -LiteralPath $tokenKey -Name ModelLanguage -Value $case.Language
        Set-ItemProperty -LiteralPath $tokenKey -Name VoiceStatePath -Value (Join-Path 'C:\Program Files\PocketTTS\voices' $case.Voice)
        Set-ItemProperty -LiteralPath (Join-Path $tokenKey 'Attributes') -Name Language -Value $case.Locale
        $voice = New-Object -ComObject SAPI.SpVoice
        $selected = New-Object -ComObject SAPI.SpObjectToken
        $selected.SetId('HKEY_CURRENT_USER\SOFTWARE\Microsoft\Speech\Voices\Tokens\PocketTTSProof7m', '', $false)
        $voice.Voice = $selected
        $samples = @()
        foreach ($pass in @('first', 'replay')) {
            $stream = New-Object -ComObject SAPI.SpFileStream
            $stream.Format.Type = 26
            $output = Join-Path $root "results\seek-cache-$($case.Language)-$pass.wav"
            $stream.Open($output, 3, $false)
            $voice.AudioOutputStream = $stream
            $timer = [Diagnostics.Stopwatch]::StartNew()
            try { $null = $voice.Speak($case.Text) }
            finally { $timer.Stop(); $stream.Close() }
            [byte[]]$bytes = [IO.File]::ReadAllBytes($output)
            if ($bytes.Length -le 44) { throw "$($case.Language) $pass returned empty audio." }
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
            finally { $sha.Dispose() }
            $samples += [pscustomobject]@{
                Language = $case.Language
                Pass = $pass
                Milliseconds = $timer.ElapsedMilliseconds
                AudioBytes = $bytes.Length
                Hash = $hash
            }
        }
        if ($samples[0].Hash -ne $samples[1].Hash) {
            throw "$($case.Language) replay returned different audio."
        }
        if ($samples[1].Milliseconds -ge $samples[0].Milliseconds) {
            throw "$($case.Language) replay was not faster than first synthesis."
        }
        $results += $samples
    }
    $results | Format-Table Language,Pass,Milliseconds,AudioBytes -AutoSize
} finally {
    if (Test-Path -LiteralPath $tokenKey) {
        $owner = (Get-ItemProperty -LiteralPath $tokenKey -Name CLSID -ErrorAction SilentlyContinue).CLSID
        if ($owner -eq $clsid) { Remove-Item -LiteralPath $tokenKey -Recurse -Force }
    }
    if (Test-Path -LiteralPath $comKey) {
        $ownerDll = (Get-Item -LiteralPath (Join-Path $comKey 'InprocServer32') -ErrorAction SilentlyContinue).GetValue('')
        if ($ownerDll -eq $dll) { Remove-Item -LiteralPath $comKey -Recurse -Force }
    }
}
