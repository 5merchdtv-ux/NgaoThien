<#
  Push-TrangThai.ps1  —  Đẩy dữ liệu công khai lên GitHub (một chiều, đi ra).

  Chạy TRÊN VPS bằng Task Scheduler mỗi 5 phút. Đẩy 3 tệp lên repo Pages:
    - data/trang-thai.json : trạng thái kênh (dò cổng client K1) — đẩy mỗi nhịp (nhịp tim)
    - data/tin-tuc.json    : tin tức lấy từ nguồn tin của Launcher — chỉ đẩy khi có thay đổi
    - data/bxh.json        : bảng xếp hạng (Cấp độ / Võ huân / PVP) — chỉ đẩy khi có thay đổi

  Người xem KHÔNG bao giờ chạm VPS: job này gom dữ liệu từ nội bộ rồi đẩy JSON tĩnh lên GitHub;
  site đọc JSON tĩnh trên GitHub Pages. Không lộ domain VPS, không hứng DDoS.
  KHÔNG đụng gameplay Kênh 1 (chỉ 1 gói TCP dò cổng). Token đọc từ biến môi trường HKNT_GH_TOKEN.
#>

# ================== CẤU HÌNH ==================
$GitHubOwner  = "5merchdtv-ux"
$GitHubRepo   = "NgaoThien"
$GitHubBranch = "main"
$TokenEnv     = "HKNT_GH_TOKEN"
$TokenFile    = "C:\HKServer\Secrets\github-status-push.token"
$K1Host       = "127.0.0.1"
$K1Port       = 15001
$NewsUrl      = "https://hkngaothien.duckdns.org/api/launcher/public/news"
$RankUrlBase  = "https://hkngaothien.duckdns.org/api/launcher/public/rankings"
$RankLimit    = 20
$ItemEventsUrl= "https://hkngaothien.duckdns.org/api/launcher/public/item-events?afterId=0&limit=80&filter=all"
# =============================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log($msg) { Write-Output ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) }

function Test-Port($ipHost, $port, $timeoutMs = 3000) {
  $client = New-Object Net.Sockets.TcpClient
  try {
    $iar = $client.BeginConnect($ipHost, $port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs)) { return $false }
    $client.EndConnect($iar); return $true
  } catch { return $false } finally { $client.Close() }
}

function Get-JobName($job) {
  switch ([int]$job) {
    1 {"Đao"} 2 {"Kiếm"} 3 {"Thương"} 4 {"Cung"} 5 {"Đại phu"} 6 {"Ninja"} 7 {"Cầm sư"}
    8 {"Hàn Bảo Quân"} 9 {"Đàm Hoa Liên"} 10 {"Quyền sư"} 11 {"Mai Liễu Chân"} 12 {"Tử Hào"} 13 {"Thần Nữ"}
    default {"Không rõ"}
  }
}
function Get-FactionName($f) { switch ([int]$f) { 1 {"Chính"} 2 {"Tà"} default {"Trung lập"} } }

# --- token ---
$token = [Environment]::GetEnvironmentVariable($TokenEnv, "Machine")
if ([string]::IsNullOrWhiteSpace($token)) { $token = [Environment]::GetEnvironmentVariable($TokenEnv) }
if ([string]::IsNullOrWhiteSpace($token) -and (Test-Path $TokenFile)) { $token = Get-Content -Raw $TokenFile }
if ([string]::IsNullOrWhiteSpace($token)) { throw "Thiếu token: đặt biến môi trường $TokenEnv hoặc tệp $TokenFile" }
$token = $token.Trim()

$headers = @{
  Authorization = "Bearer $token"; "User-Agent" = "HKNT-Status-Pusher"
  Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28"
}

# Đẩy 1 tệp NHƯNG chỉ khi nội dung khác bản trên repo (tránh commit rác).
function Push-IfChanged($relPath, $jsonString, $message) {
  $api = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/contents/$relPath"
  $sha = $null; $current = $null
  try {
    $existing = Invoke-RestMethod -Uri ("{0}?ref={1}" -f $api, $GitHubBranch) -Headers $headers -TimeoutSec 30
    $sha = $existing.sha
    if ($existing.content) { $current = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($existing.content -replace "\s",""))) }
  } catch {
    if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404)) { throw }
    Write-Log ("$relPath chưa có, sẽ tạo mới.")
  }
  if ($null -ne $current -and $current.Trim() -eq $jsonString.Trim()) {
    Write-Log ("$relPath không đổi — bỏ qua."); return
  }
  $body = @{ message = $message; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($jsonString)); branch = $GitHubBranch }
  if ($sha) { $body.sha = $sha }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress))
  $resp = Invoke-RestMethod -Uri $api -Method Put -Headers $headers -Body $bytes -ContentType "application/json" -TimeoutSec 30
  Write-Log ("$relPath ĐÃ đẩy. Commit: {0}" -f $resp.commit.sha)
}

# ===== 1) TRẠNG THÁI KÊNH =====
$k1Open = Test-Port $K1Host $K1Port
Write-Log ("Cổng Kênh 1 {0}:{1} -> {2}" -f $K1Host, $K1Port, ($(if ($k1Open) {"MỞ"} else {"đóng"})))
$k1 = if ($k1Open) { [ordered]@{ ten="Kênh 1"; trangThai="open"; ghiChu="Hoạt động bình thường" } }
      else          { [ordered]@{ ten="Kênh 1"; trangThai="maintenance"; ghiChu="Đang bảo trì" } }
$k2 = [ordered]@{ ten="Kênh 2"; trangThai="maintenance"; ghiChu="Kênh thử nghiệm" }
$trangThai = [ordered]@{ capNhat=(Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz"); kenh=@($k1,$k2) }
Push-IfChanged "data/trang-thai.json" ($trangThai | ConvertTo-Json -Depth 6) ("cập nhật trạng thái kênh " + (Get-Date -Format "yyyy-MM-dd HH:mm"))

# ===== 2) TIN TỨC (từ nguồn tin của Launcher) =====
try {
  $news = Invoke-RestMethod -Uri $NewsUrl -TimeoutSec 30
  $tin = @()
  foreach ($n in $news) {
    $tin += [pscustomobject][ordered]@{
      ngay    = [string]$n.date
      badge   = [string]$n.badge
      tieuDe  = [string]$n.title
      noiDung = [string]$n.description
      anh     = [string]$n.imageUrl
      tacGia  = [string]$n.author
    }
  }
  $tinJson = [ordered]@{ tinTuc = @($tin) } | ConvertTo-Json -Depth 6
  Push-IfChanged "data/tin-tuc.json" $tinJson "cập nhật tin tức"
} catch { Write-Log ("Bỏ qua tin tức (lỗi nguồn): {0}" -f $_.Exception.Message) }

# ===== 3) BẢNG XẾP HẠNG =====
try {
  $bxh = [ordered]@{}
  foreach ($t in @("level","wx","pvp")) {
    $rows = Invoke-RestMethod -Uri ("{0}?type={1}&limit={2}" -f $RankUrlBase, $t, $RankLimit) -TimeoutSec 30
    $arr = @()
    foreach ($r in $rows) {
      $arr += [pscustomobject][ordered]@{
        rank    = [int]$r.rank
        ten     = [string]$r.characterName
        nghe    = Get-JobName $r.job
        phai    = Get-FactionName $r.faction
        cap     = [int]$r.level
        capNghe = [int]$r.jobLevel
        bang    = [string]$r.guildName
        thanhTuu= [string]$r.achievement
      }
    }
    $bxh[$t] = @($arr)
  }
  $bxhJson = $bxh | ConvertTo-Json -Depth 6
  Push-IfChanged "data/bxh.json" $bxhJson "cập nhật bảng xếp hạng"
} catch { Write-Log ("Bỏ qua BXH (lỗi nguồn): {0}" -f $_.Exception.Message) }

# ===== 4) CƯỜNG HÓA TRỰC TUYẾN (feed đập đồ / hợp thành) =====
try {
  $events = Invoke-RestMethod -Uri ($ItemEventsUrl) -TimeoutSec 30
  $ds = @()
  foreach ($e in $events) {
    $loai = if ($e.eventType -eq "HOP_THANH") { "hop-thanh" } else { "cuong-hoa" }
    if ($e.eventType -eq "HOP_THANH") {
      $thayDoi = [string]$e.attributeText
    } else {
      $before = if ($null -ne $e.beforeLevel) { "+" + $e.beforeLevel } else { "?" }
      $after  = if ($null -ne $e.afterLevel)  { "+" + $e.afterLevel }  else { "mất vật phẩm" }
      $thayDoi = "$before → $after"
      if ((-not $e.success) -and $e.failureEffect) { $thayDoi += " • " + $e.failureEffect }
    }
    $tg = try { ([DateTime]::SpecifyKind([DateTime]$e.createdAt, 'Utc')).ToLocalTime().ToString("HH:mm:ss") } catch { "" }
    $ds += [pscustomobject][ordered]@{
      thoiGian   = $tg
      kenh       = [int]$e.channelId
      nhanVat    = [string]$e.characterName
      loai       = $loai
      trangBi    = [string]$e.itemName
      nguyenLieu = if ([string]::IsNullOrWhiteSpace($e.materialName)) { "—" } else { [string]$e.materialName }
      thayDoi    = $thayDoi
      thanhCong  = [bool]$e.success
    }
  }
  $chJson = [ordered]@{ danhSach = @($ds) } | ConvertTo-Json -Depth 6
  Push-IfChanged "data/cuong-hoa.json" $chJson "cập nhật cường hóa trực tuyến"
} catch { Write-Log ("Bỏ qua cường hóa (lỗi nguồn): {0}" -f $_.Exception.Message) }

Write-Log "Xong."
