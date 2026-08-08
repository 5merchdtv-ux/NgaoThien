<#
  Push-TrangThai.ps1  —  Đẩy trạng thái kênh lên GitHub (một chiều, đi ra).

  Chạy TRÊN VPS bằng Task Scheduler mỗi 5 phút. Kịch bản:
    1) Thử kết nối TCP tới cổng client Kênh 1 (mặc định 15001) — đúng như client người chơi
    2) Suy ra trạng thái: Kênh 1 mở nếu cổng lắng nghe; Kênh 2 luôn Bảo trì (kênh thử nghiệm)
    3) Ghi đè data/trang-thai.json trên repo GitHub qua GitHub Contents API

  KHÔNG mở cổng nào cho internet. KHÔNG đụng gameplay Kênh 1 (chỉ 1 gói TCP mở/đóng).
  Token đọc từ tệp bí mật KHÔNG commit lên repo.
#>

# ================== CẤU HÌNH — sửa cho khớp ==================
$GitHubOwner  = "5merchdtv-ux"                 # tài khoản GitHub
$GitHubRepo   = "NgaoThien"                    # repo public chứa site
$GitHubBranch = "main"
$FilePath     = "data/trang-thai.json"
$TokenFile    = "C:\HKServer\Secrets\github-status-push.token"  # PAT fine-grained, chỉ repo này, quyền Contents: Read+Write
$K1Host       = "127.0.0.1"
$K1Port       = 15001                          # cổng client Kênh 1 (K2 = 15002)
# ============================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log($msg) {
  Write-Output ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg)
}

# --- 1. Kiểm cổng client Kênh 1 (một gói TCP, không đụng gameplay) ---
function Test-Port($ipHost, $port, $timeoutMs = 3000) {
  $client = New-Object Net.Sockets.TcpClient
  try {
    $iar = $client.BeginConnect($ipHost, $port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs)) { return $false }
    $client.EndConnect($iar)
    return $true
  } catch { return $false }
  finally { $client.Close() }
}

$k1Open = Test-Port $K1Host $K1Port
Write-Log ("Cổng Kênh 1 {0}:{1} -> {2}" -f $K1Host, $K1Port, ($(if ($k1Open) {"MỞ"} else {"đóng"})))
$k1 = if ($k1Open) { @{ ten = "Kênh 1"; trangThai = "open";        ghiChu = "Hoạt động bình thường" } }
      else          { @{ ten = "Kênh 1"; trangThai = "maintenance"; ghiChu = "Đang bảo trì"          } }
# Kênh 2 là kênh thử nghiệm, luôn đóng với người chơi
$k2 = @{ ten = "Kênh 2"; trangThai = "maintenance"; ghiChu = "Kênh thử nghiệm" }

$payload = [ordered]@{
  capNhat = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
  kenh    = @($k1, $k2)
}
$json = ($payload | ConvertTo-Json -Depth 5)
Write-Log "Nội dung mới:`n$json"

# --- 2. Đẩy lên GitHub Contents API ---
if (-not (Test-Path $TokenFile)) { throw "Thiếu tệp token: $TokenFile" }
$token = (Get-Content -Raw $TokenFile).Trim()

$headers = @{
  Authorization          = "Bearer $token"
  "User-Agent"           = "HKNT-Status-Pusher"
  Accept                 = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
}
$apiBase = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/$FilePath"

# Lấy sha hiện tại (nếu tệp đã tồn tại)
$sha = $null
try {
  $existing = Invoke-RestMethod -Uri ("{0}?ref={1}" -f $apiBase, $GitHubBranch) -Headers $headers -TimeoutSec 30
  $sha = $existing.sha
} catch {
  if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
    Write-Log "Tệp chưa tồn tại trên repo, sẽ tạo mới."
  } else { throw }
}

$contentB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
$body = @{
  message = "cập nhật trạng thái kênh " + (Get-Date -Format "yyyy-MM-dd HH:mm")
  content = $contentB64
  branch  = $GitHubBranch
}
if ($sha) { $body.sha = $sha }

$resp = Invoke-RestMethod -Uri $apiBase -Method Put -Headers $headers -Body ($body | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 30
Write-Log ("Đã đẩy. Commit: {0}" -f $resp.commit.sha)
