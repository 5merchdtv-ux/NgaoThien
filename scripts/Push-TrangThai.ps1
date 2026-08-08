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

# Sửa tên vật phẩm hỏng dấu tiếng Việt (port từ lib/vni-fix.ts nội bộ — CHỈ để hiển thị).
# Dùng Hashtable phân biệt hoa/thường (literal @{} của PowerShell không phân biệt → trùng key).
$Script:VNI_BASE = [System.Collections.Hashtable]::new()
$VNI_BASE['ý']='ư'; $VNI_BASE['Ý']='Ư'; $VNI_BASE['õ']='ơ'; $VNI_BASE['Õ']='Ơ'
$VNI_BASE['ã']='ă'; $VNI_BASE['Ã']='Ă'; $VNI_BASE['ð']='đ'; $VNI_BASE['Ð']='Đ'
$Script:VNI_TONE = [System.Collections.Hashtable]::new()
$VNI_TONE['ì']=[char]0x0301; $VNI_TONE['Ì']=[char]0x0300; $VNI_TONE['Ò']=[char]0x0309
$VNI_TONE['Þ']=[char]0x0303; $VNI_TONE['ò']=[char]0x0323
$Script:VNI_VOWELS = 'aăâeêioôơuưyAĂÂEÊIOÔƠUƯY'
function Fix-VN($text) {
  if ([string]::IsNullOrEmpty($text)) { return $text }
  $broken = ($text -match '[ÌÒÞðÐ]') -or ($text -match "[$VNI_VOWELS][ìò]")
  if (-not $broken) { return $text }
  $out = New-Object System.Text.StringBuilder
  foreach ($ch in $text.ToCharArray()) {
    $s = [string]$ch
    if ($VNI_TONE.ContainsKey($s)) {
      $prev = if ($out.Length -gt 0) { [string]$out[$out.Length - 1] } else { '' }
      if ($prev -and $VNI_VOWELS.Contains($prev)) { [void]$out.Append($VNI_TONE[$s]); continue }
      [void]$out.Append($s); continue
    }
    if ($VNI_BASE.ContainsKey($s)) { [void]$out.Append($VNI_BASE[$s]) } else { [void]$out.Append($s) }
  }
  return $out.ToString().Normalize([Text.NormalizationForm]::FormC)
}

# Tên dòng thuộc tính (khớp ATTRIBUTE_NAMES trong dashboard) để dịch "Loại N +V" của hợp thành.
$Script:ATTR = @{
  1='Sức tấn công'; 2='Sức phòng ngự'; 3='Sinh mệnh (HP)'; 4='Nội công (MP)'; 5='Chính xác';
  6='Né tránh'; 7='Công lực võ công'; 8='Khí công'; 9='Tỷ lệ hợp thành/cường hóa'; 10='Điểm đả kích';
  11='Phòng ngự võ công'; 12='Tiền nhận được'; 13='Giảm tổn thất EXP'
}
$Script:ATTR_PCT = @(7, 9, 12, 13)
function Format-HopThanh($attributeText) {
  if ($attributeText -match 'Loại\s+(\d+)\s*\+\s*(\d+)') {
    $type = [int]$Matches[1]; $val = $Matches[2]
    # Loại 8 = dòng khí công đặc biệt, dòng phụ (vd "Hồi liễu thân pháp") KHÔNG có trong log → không khẳng định.
    if ($type -eq 8) { return "Hiệu ứng đặc biệt +$val" }
    $name = if ($ATTR.ContainsKey($type)) { $ATTR[$type] } else { "Loại $type" }
    $pct = if ($ATTR_PCT -contains $type) { "%" } else { "" }
    return "$name +$val$pct"
  }
  return [string]$attributeText
}

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

# ===== DB read-only (chuỗi kết nối đọc từ config LoginServer lúc chạy — KHÔNG lưu mật khẩu vào repo) =====
$LoginConfig = "C:\HKServer\Server\LoginServer\bin\Debug\config.ini"
$GameDb   = "v22Game_Hkgiangho"
$PublicDb = "v22PublicDB_HKgiangho"
$Script:ItemLevel = @{}
$dbConn = $null
try {
  function Read-Ini($k) { (Get-Content $LoginConfig | Where-Object { $_ -match "^\s*$k\s*=" } | Select-Object -First 1) -replace "^\s*$k\s*=\s*","" -replace "\s+$","" }
  $connStr = "Server=$(Read-Ini 'Server');User Id=$(Read-Ini 'UserName');Password=$(Read-Ini 'PassWord');TrustServerCertificate=True;Connect Timeout=15"
  $dbConn = New-Object System.Data.SqlClient.SqlConnection $connStr
  $dbConn.Open()
  # Map PID -> level trang bị (cho feed cường hóa)
  $ic = $dbConn.CreateCommand(); $ic.Connection.ChangeDatabase($PublicDb)
  $ic.CommandText = "SELECT FLD_PID, FLD_LEVEL FROM TBL_XWWL_ITEM WITH(NOLOCK)"
  $ir = $ic.ExecuteReader(); while ($ir.Read()) { $Script:ItemLevel[[int]$ir['FLD_PID']] = [int]$ir['FLD_LEVEL'] }; $ir.Close()
  Write-Log ("Đã nạp {0} level trang bị." -f $Script:ItemLevel.Count)
} catch { Write-Log ("Không kết nối được DB (BXH/level sẽ bỏ qua): {0}" -f $_.Exception.Message) }

# ===== 3) BẢNG XẾP HẠNG (đọc DB read-only — võ huân/cấp ĐÚNG; bỏ PVP vì toàn 0) =====
if ($dbConn -and $dbConn.State -eq 'Open') {
  try {
    function Get-Rank($orderBy, $valCol) {
      $c = $dbConn.CreateCommand(); $c.Connection.ChangeDatabase($GameDb)
      $c.CommandText = "SELECT TOP $RankLimit FLD_NAME, ISNULL(FLD_JOB,0) job, ISNULL(FLD_ZX,0) zx, ISNULL(FLD_LEVEL,0) lv, ISNULL(FLD_JOB_LEVEL,0) jl, ISNULL($valCol,0) val, CONVERT(bit,CASE WHEN ISNULL(FLD_ONLINE,0)<>0 THEN 1 ELSE 0 END) onl FROM TBL_XWWL_Char WITH(NOLOCK) WHERE ISNULL(FLD_J9,0)=0 AND ISNULL(FLD_NAME,'')<>'' ORDER BY $orderBy"
      $t = New-Object System.Data.DataTable; [void]$t.Load($c.ExecuteReader()); ,$t
    }
    function Build-Rank($tbl) {
      $arr = @(); $i = 0
      foreach ($row in $tbl.Rows) {
        $i++
        $arr += [pscustomobject][ordered]@{
          rank = $i; ten = [string]$row['FLD_NAME']; nghe = Get-JobName $row['job']; phai = Get-FactionName $row['zx']
          cap = [int]$row['lv']; capNghe = [int]$row['jl']; online = [bool]$row['onl']; thanhTuu = [string]([int64]$row['val'])
        }
      }
      return ,@($arr)
    }
    $expOrder = "FLD_LEVEL DESC, (CASE WHEN ISNUMERIC(FLD_EXP)=1 THEN CAST(FLD_EXP AS decimal(38,0)) ELSE 0 END) DESC, FLD_NAME ASC"
    $bxh = [ordered]@{
      level = Build-Rank (Get-Rank $expOrder 'FLD_LEVEL')
      wx    = Build-Rank (Get-Rank "ISNULL(FLD_WX,0) DESC, ISNULL(FLD_LEVEL,0) DESC, FLD_NAME ASC" 'FLD_WX')
    }
    Push-IfChanged "data/bxh.json" ($bxh | ConvertTo-Json -Depth 6) "cập nhật bảng xếp hạng"
  } catch { Write-Log ("Bỏ qua BXH (lỗi truy vấn): {0}" -f $_.Exception.Message) }
}

# ===== 4) CƯỜNG HÓA TRỰC TUYẾN (feed đập đồ / hợp thành) =====
try {
  $events = Invoke-RestMethod -Uri ($ItemEventsUrl) -TimeoutSec 30
  $ds = @()
  foreach ($e in $events) {
    $loai = if ($e.eventType -eq "HOP_THANH") { "hop-thanh" } else { "cuong-hoa" }
    if ($e.eventType -eq "HOP_THANH") {
      $thayDoi = Format-HopThanh ([string]$e.attributeText)   # Loại 1-13 → tên thuộc tính; Loại 8 chỉ ra "Khí công" (dòng phụ không có trong log)
    } else {
      $before = if ($null -ne $e.beforeLevel) { "+" + $e.beforeLevel } else { "?" }
      $after  = if ($null -ne $e.afterLevel)  { "+" + $e.afterLevel }  else { "mất vật phẩm" }
      $thayDoi = "$before → $after"
      if ((-not $e.success) -and $e.failureEffect) { $thayDoi += " • " + $e.failureEffect }
    }
    $tg = try { ([DateTime]::SpecifyKind([DateTime]$e.createdAt, 'Utc')).ToLocalTime().ToString("HH:mm:ss") } catch { "" }
    $capDo = if ($e.itemPid -and $Script:ItemLevel.ContainsKey([int]$e.itemPid)) { [string]$Script:ItemLevel[[int]$e.itemPid] } else { "—" }
    $ds += [pscustomobject][ordered]@{
      thoiGian   = $tg
      kenh       = [int]$e.channelId
      nhanVat    = [string]$e.characterName
      loai       = $loai
      trangBi    = Fix-VN ([string]$e.itemName)
      capDo      = $capDo
      nguyenLieu = if ([string]::IsNullOrWhiteSpace($e.materialName)) { "—" } else { Fix-VN ([string]$e.materialName) }
      thayDoi    = $thayDoi
      thanhCong  = [bool]$e.success
    }
  }
  $chJson = [ordered]@{ danhSach = @($ds) } | ConvertTo-Json -Depth 6
  Push-IfChanged "data/cuong-hoa.json" $chJson "cập nhật cường hóa trực tuyến"
} catch { Write-Log ("Bỏ qua cường hóa (lỗi nguồn): {0}" -f $_.Exception.Message) }

if ($dbConn) { try { $dbConn.Close() } catch {} }
Write-Log "Xong."
