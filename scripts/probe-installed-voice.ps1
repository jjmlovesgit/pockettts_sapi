param(
    [Parameter(Mandatory=$true)][string]$TokenId,
    [string]$Text='This is a test of the selected Pocket TTS voice.'
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$key="Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\$TokenId"
if (-not (Test-Path -LiteralPath $key)) { throw "Missing token: $TokenId" }
$properties=Get-ItemProperty -LiteralPath $key
if ($properties.CLSID -ne '{52586884-b3dc-46c5-a298-a49606cc5421}') { throw "Not a Pocket TTS token: $TokenId" }
if (-not (Test-Path -LiteralPath $properties.VoiceStatePath)) { throw "Missing voice state: $TokenId" }
$voice=New-Object -ComObject SAPI.SpVoice
$selected=New-Object -ComObject SAPI.SpObjectToken
$stream=New-Object -ComObject SAPI.SpFileStream
try {
    $selected.SetId("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\$TokenId",'', $false)
    $voice.Voice=$selected
    $output=Join-Path $root ("results\voice-probe-"+($TokenId -replace '[^A-Za-z0-9_.-]','_')+'.wav')
    $stream.Format.Type=26
    $stream.Open($output,3,$false)
    $voice.AudioOutputStream=$stream
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try { $null=$voice.Speak($Text) } finally { $timer.Stop(); $stream.Close() }
    $bytes=(Get-Item -LiteralPath $output).Length
    if ($bytes -le 44) { throw 'No speech generated.' }
    $worker=Get-ItemProperty 'Registry::HKEY_CURRENT_USER\Software\PocketTTS' -ErrorAction Stop
    [pscustomobject]@{Token=$TokenId;ExpectedVoice=$properties.VoiceStatePath;WorkerVoice=$worker.WorkerVoice;WorkerLanguage=$worker.WorkerLanguage;Milliseconds=$timer.ElapsedMilliseconds;WavBytes=$bytes;Output=$output}
} finally {
    [Runtime.InteropServices.Marshal]::ReleaseComObject($stream) | Out-Null
    [Runtime.InteropServices.Marshal]::ReleaseComObject($selected) | Out-Null
    [Runtime.InteropServices.Marshal]::ReleaseComObject($voice) | Out-Null
}
