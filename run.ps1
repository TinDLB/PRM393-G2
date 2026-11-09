param(
    [string]$SqlConnectionString = 'Server=localhost\SQL2022;Database=YoutubeSimulationDb;Integrated Security=True;Encrypt=True;TrustServerCertificate=True',
    [string]$MediaRoot = 'D:\youtube-media'
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$apiDirectory = Join-Path $projectRoot 'backend\YoutubeSimulation.Api'
$apiProject = Join-Path $apiDirectory 'YoutubeSimulation.Api.csproj'
$apiAssembly = Join-Path $apiDirectory 'bin\Debug\net10.0\YoutubeSimulation.Api.dll'
$apiUrl = 'http://127.0.0.1:5296'
$apiStartedHere = $false
$apiProcess = $null
$stdoutLog = Join-Path $env:TEMP 'youtube-simulation-api.stdout.log'
$stderrLog = Join-Path $env:TEMP 'youtube-simulation-api.stderr.log'

function Test-ApiReady {
    try {
        $response = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
        return $response.status -eq 'ready'
    } catch {
        return $false
    }
}

function Stop-StartedApi {
    if (-not $script:apiStartedHere) {
        return
    }
    if ($script:apiProcess -and -not $script:apiProcess.HasExited) {
        Stop-Process -Id $script:apiProcess.Id -Force
        Wait-Process -Id $script:apiProcess.Id -Timeout 10 -ErrorAction SilentlyContinue
    }
    foreach ($logPath in @($script:stdoutLog, $script:stderrLog)) {
        if (Test-Path -LiteralPath $logPath) {
            try {
                Remove-Item -LiteralPath $logPath -Force -ErrorAction Stop
            } catch {
                Write-Warning "Could not remove temporary API log: $logPath"
            }
        }
    }
}

Push-Location $projectRoot
try {
    $chromePath = $env:CHROME_EXECUTABLE
    if (-not $chromePath) {
        $chromePaths = @(
            (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
        )
        $chromePath = $chromePaths | Where-Object {
            Test-Path -LiteralPath $_
        } | Select-Object -First 1
    }
    if (-not $chromePath) {
        throw 'Google Chrome was not found. Install Chrome or set CHROME_EXECUTABLE.'
    }
    $env:CHROME_EXECUTABLE = $chromePath

    $apiReady = Test-ApiReady
    if (-not $apiReady) {
        $portOwner = Get-NetTCPConnection -State Listen -LocalPort 5296 `
            -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($portOwner) {
            throw 'Port 5296 is in use but the API is not ready. Stop the process using that port and retry.'
        }
    }

    Write-Host 'Building the API...' -ForegroundColor Cyan
    & dotnet build $apiProject --no-restore --maxcpucount:1
    if ($LASTEXITCODE -ne 0) {
        throw 'API build failed. See the build output above.'
    }

    if (-not $apiReady) {
        if (-not (Test-Path -LiteralPath $MediaRoot)) {
            New-Item -ItemType Directory -Path $MediaRoot -Force | Out-Null
        }

        $oldConnectionString = $env:ConnectionStrings__YoutubeSimulationDb
        $oldMediaRoot = $env:Media__Root
        $oldUrls = $env:ASPNETCORE_URLS
        $oldEnvironment = $env:ASPNETCORE_ENVIRONMENT
        try {
            $env:ConnectionStrings__YoutubeSimulationDb = $SqlConnectionString
            $env:Media__Root = $MediaRoot
            $env:ASPNETCORE_URLS = 'http://0.0.0.0:5296'
            $env:ASPNETCORE_ENVIRONMENT = 'Development'
            $script:apiProcess = Start-Process -FilePath 'dotnet' `
                -ArgumentList "`"$apiAssembly`"" `
                -WorkingDirectory $apiDirectory `
                -PassThru `
                -WindowStyle Hidden `
                -RedirectStandardOutput $stdoutLog `
                -RedirectStandardError $stderrLog
            $script:apiStartedHere = $true
        } finally {
            $env:ConnectionStrings__YoutubeSimulationDb = $oldConnectionString
            $env:Media__Root = $oldMediaRoot
            $env:ASPNETCORE_URLS = $oldUrls
            $env:ASPNETCORE_ENVIRONMENT = $oldEnvironment
        }

        $apiReady = $false
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            if ($script:apiProcess.HasExited) {
                break
            }
            if (Test-ApiReady) {
                $apiReady = $true
                break
            }
            Start-Sleep -Seconds 1
        }
        if (-not $apiReady) {
            if (Test-Path -LiteralPath $stderrLog) {
                Get-Content -LiteralPath $stderrLog -Tail 30
            }
            throw 'API did not start. Check SQL Server localhost\SQL2022, YoutubeSimulationDb, and database access.'
        }
    }

    Write-Host 'API is ready. Starting the app in Chrome at http://localhost:7357.' `
        -ForegroundColor Green
    & flutter run -d chrome --web-hostname=localhost --web-port=7357 `
        --dart-define=API_BASE_URL=http://localhost:5296
    if ($LASTEXITCODE -ne 0) {
        throw 'Flutter Web run failed. See the output above.'
    }
} finally {
    Stop-StartedApi
    Pop-Location
}
