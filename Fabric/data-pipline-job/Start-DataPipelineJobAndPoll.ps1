<#
.SYNOPSIS
  Start a Fabric Data Pipeline job and poll its status until completion, refreshing tokens as needed.
#>

param (
  [ValidateSet("UserPrincipal","ServicePrincipal")]
  [string] $PrincipalType = "ServicePrincipal",

  [Parameter(Mandatory)][string] $WorkspaceId,
  [Parameter(Mandatory)][string] $ItemId,

  [string] $ClientId,
  [string] $TenantId,
  [string] $ClientSecret
)

$JobType     = "Pipeline"
$BaseUrl     = "https://api.fabric.microsoft.com/v1"
$ResourceUrl = "https://api.fabric.microsoft.com"

function Get-FabricHeaders {
    param(
        [ValidateSet("UserPrincipal","ServicePrincipal")] [string] $PrincipalType,
        [string] $ClientId,
        [string] $TenantId,
        [string] $ClientSecret,
        [string] $ResourceUrl
    )

    if ($PrincipalType -eq "UserPrincipal") {
        Connect-AzAccount | Out-Null
    } else {
        $sec  = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($ClientId, $sec)
        Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $cred | Out-Null
    }

    $token = (Get-AzAccessToken -ResourceUrl $ResourceUrl).Token
    return @{ 'Authorization' = "Bearer $token"; 'Content-Type' = 'application/json' }
}

function Start-PipelineJob {
    param(
        [string]   $BaseUrl,
        [string]   $WorkspaceId,
        [string]   $ItemId,
        [string]   $JobType,
        [hashtable] $Headers
    )

    $url = "$BaseUrl/workspaces/$WorkspaceId/items/$ItemId/jobs/instances?jobType=$JobType"
    Write-Host "▶ Starting Pipeline job at: $url"

    try {
        $resp = Invoke-WebRequest -Uri $url -Method Post -Headers $Headers -Body '{}' -ErrorAction Stop
        Write-Host "✅ Job started (StatusCode: $($resp.StatusCode))" -ForegroundColor Green
        return $resp.Headers
    } catch {
        Write-Host "❌ Failed to start job: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            $ex = $_.Exception.Response
            Write-Host "  HTTP Status: $($ex.StatusCode) $($ex.StatusDescription)"
            Write-Host "  -- Response Headers --"
            $ex.Headers.GetEnumerator() | ForEach-Object { Write-Host "    $($_.Name): $((@($_.Value) -join ','))" }
            Write-Host "  -- Response Body --"
            $reader = [System.IO.StreamReader]::new($ex.GetResponseStream())
            Write-Host $reader.ReadToEnd()
        }
        exit 1
    }
}

#--- 実行フロー ---#
$headers     = Get-FabricHeaders -PrincipalType $PrincipalType -ClientId $ClientId -TenantId $TenantId -ClientSecret $ClientSecret -ResourceUrl $ResourceUrl
$respHeaders = Start-PipelineJob -BaseUrl $BaseUrl -WorkspaceId $WorkspaceId -ItemId $ItemId -JobType $JobType -Headers $headers

# Retry-After
$retryAfterValue = $respHeaders['Retry-After']
if ($retryAfterValue -is [array] -and $retryAfterValue.Count -gt 0) {
    $retryAfter = [int]$retryAfterValue[0]
} elseif ($retryAfterValue) {
    $retryAfter = [int]$retryAfterValue
} else {
    $retryAfter = 30
}
Write-Host "⏱ Poll interval: $retryAfter seconds"

# Location
$locationValue = $respHeaders['Location']
if ($locationValue -is [array] -and $locationValue.Count -gt 0) {
    $location = [string]$locationValue[0]
} elseif ($locationValue) {
    $location = [string]$locationValue
} else {
    Write-Error 'Location header missing. Cannot poll status.'
    exit 1
}
Write-Host "🔄 Polling at: $location"

# Poll loop
do {
    $headers = Get-FabricHeaders -PrincipalType $PrincipalType -ClientId $ClientId -TenantId $TenantId -ClientSecret $ClientSecret -ResourceUrl $ResourceUrl
    Start-Sleep -Seconds $retryAfter
    $statusResp = Invoke-RestMethod -Uri $location -Method Get -Headers $headers -ErrorAction Stop
    $state      = $statusResp.status
    Write-Host "$(Get-Date -Format u) → ステータス: $state"
} while ($state -in @('NotStarted','InProgress'))

# Result
if ($state -eq 'Completed') {
    Write-Host '✅ Job completed successfully.'
    exit 0
} else {
    Write-Host "❌ Job ended with status: $state"
    if ($statusResp.failureReason) {
        Write-Host "Error detail: $($statusResp.failureReason | ConvertTo-Json -Depth 4)"
    }
    exit 1
}
