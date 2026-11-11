$ErrorActionPreference = 'Stop'
$roots = @(
    'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Speech\Voices\Tokens',
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens',
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens'
)
$clsid = '{52586884-b3dc-46c5-a298-a49606cc5421}'
foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root | Where-Object { $_.PSChildName.StartsWith('PocketTTS.Custom.') } | ForEach-Object {
        $registered = (Get-ItemProperty -LiteralPath $_.PSPath -Name CLSID -ErrorAction SilentlyContinue).CLSID
        if ($registered -eq $clsid) { Remove-Item -LiteralPath $_.PSPath -Recurse -Force }
    }
}
# Voice-state files are intentionally preserved in user profiles. They are user
# data and can be imported again after reinstalling the base package.
