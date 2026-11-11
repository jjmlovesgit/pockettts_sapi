$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$install='C:\Program Files\PocketTTS'
$manifest=Get-Content (Join-Path $root 'packaging\language-packs.json') -Raw | ConvertFrom-Json
$pack=@($manifest.packs | Where-Object id -eq german)[0]
$token='PocketTTS.Locale.german'
$classic="Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\$token"
$oneCore="Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\$token"
foreach ($key in @($classic,$oneCore)) {
    if (-not (Test-Path -LiteralPath $key)) { throw "Missing token: $key" }
    $properties=Get-ItemProperty -LiteralPath $key
    if ($properties.CLSID -ne '{52586884-B3DC-46C5-A298-A49606CC5421}' -or $properties.ModelLanguage -ne 'german') { throw "Wrong token metadata: $key" }
    if (-not (Test-Path -LiteralPath $properties.VoiceStatePath)) { throw "Missing voice state: $key" }
}
foreach ($asset in $pack.assets) {
    $path=Join-Path $install ($asset.installPath -replace '/','\')
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing installed asset: $path" }
    if ((Get-Item -LiteralPath $path).Length -ne [int64]$asset.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne ([string]$asset.sha256).ToUpperInvariant()) { throw "Installed asset mismatch: $path" }
}
$results=@()
foreach ($case in @(
    @{Name='first';Text='Freut mich! Es freut mich, dich kennenzulernen.'},
    @{Name='warm';Text='Guten Morgen. Das ist der zweite Satz.'}
)) {
    $voice=New-Object -ComObject SAPI.SpVoice
    $selected=New-Object -ComObject SAPI.SpObjectToken
    $selected.SetId("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\$token",'', $false)
    $voice.Voice=$selected
    $stream=New-Object -ComObject SAPI.SpFileStream
    $output=Join-Path $root "results\installed-juergen-$($case.Name).wav"
    $stream.Format.Type=26
    $stream.Open($output,3,$false)
    $voice.AudioOutputStream=$stream
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try { $null=$voice.Speak($case.Text) } finally { $timer.Stop(); $stream.Close() }
    $bytes=(Get-Item -LiteralPath $output).Length
    if ($bytes -le 44) { throw "Silent output: $($case.Name)" }
    $worker=@(Get-NetTCPConnection -LocalPort 18765 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
    $results += [pscustomobject]@{Case=$case.Name;Milliseconds=$timer.ElapsedMilliseconds;WorkerPid=if($worker){$worker[0].OwningProcess}else{$null};WavBytes=$bytes;Output=$output}
}
if ($results[0].WorkerPid -ne $results[1].WorkerPid) { throw 'Worker restarted between German sentences.' }
$results | Format-Table -AutoSize | Out-String | Write-Host
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'results\installed-juergen-result.json') -Encoding utf8
