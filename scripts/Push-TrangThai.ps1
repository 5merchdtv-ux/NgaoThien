<#
  Push-TrangThai.ps1  —  Đẩy trạng thái kênh lên GitHub (một chiều, đi ra).

  Chạy TRÊN VPS bằng Task Scheduler mỗi 5 phút. Kịch bản:
    1) Gọi gateway loopback http://127.0.0.1:18082/status  (chỉ nội bộ máy)
    2) Suy ra trạng thái người chơi: Kênh 1 mở nếu process online; Kênh 2 luôn Bảo trì
    3) Ghi đè data/trang-thai.json trên repo GitHub qua GitHub Contents API

  KHÔNG mở cổng nào cho internet. KHÔNG đụng Kênh 1 (chỉ đọc /status).
  Token đọc từ tệp bí mật KHÔNG commit lên repo.
#>

# ================== CẤU HÌNH — sửa cho khớp ==================
$GitHubOwner  = "TEN_TAI_KHOAN_GITHUB"        # ví dụ: hknt-community
$GitHubRepo   = "hknt-status"                  # tên repo public chứa site
$GitHubBranch = "main"
$FilePath     = "data/trang-thai.json"
$TokenFile    = "C:\HKServer\Secrets\github-status-push.token"  # PAT fine-grained, chỉ repo này, quyền Contents: Read+Write
$GatewayUrl   = "http://127.0.0.1:18082/status"
# ============================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log($msg) {
  Write-Output ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg)
}

# --- 1. Đọc trạng thái từ gateway nội bộ ---
$activeChannels = @()
try {
  $status = Invoke-RestMethod -Uri $GatewayUrl -TimeoutSec 20
  if ($status -and $status.activeChannels) { $activeChannels = @($status.activeChannels) }
  Write-Log ("Kênh online theo gateway: {0}" -f ($activeChannels -join ", "))
} catch {
  Write-Log ("KHÔNG gọi được gateway ({0}). Giữ nguyên trạng thái cũ, không đẩy." -f $_.Exception.Message)
  exit 0   # không ghi đè để tránh nhấp nháy trạng thái sai
}

$k1Open = $activeChannels -contains 1
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
