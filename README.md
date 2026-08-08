# HK Ngạo Thiên — Trang trạng thái công khai

Trang tĩnh cho anh em xem **trạng thái kênh**, **tin tức**, và **nút tải Launcher / Game**.
Thay cho việc mở launcher chỉ để xem server còn sống không.

## Vì sao an toàn (không lo DDoS / lộ VPS)

Luồng dữ liệu **một chiều, chỉ đi ra**:

```
VPS nội bộ ──đẩy (GitHub API, outbound)──► GitHub repo ──► GitHub Pages (CDN Fastly) ──► anh em
```

- VPS **chủ động đẩy** `data/trang-thai.json` lên GitHub. Không mở cổng nào cho internet.
- Trang là **tĩnh 100%**, chỉ đọc file JSON cùng origin trên GitHub Pages. **Không có route nào gọi về VPS** → không dò ra được VPS, DDoS không xuyên qua được.
- Site này sập cũng **không ảnh hưởng game** (khác hạ tầng hoàn toàn).
- **Không dùng Vercel** → không tốn quota Vercel của dashboard nội bộ.

> ⚠️ Repo này là PUBLIC. Không đặt bất cứ thứ gì nội bộ vào đây: không IP VPS, không token, không mật khẩu, không số liệu nhạy cảm.

## Cấu trúc

| Tệp | Ai cập nhật | Mục đích |
|---|---|---|
| `data/trang-thai.json` | **Script tự đẩy** mỗi 5 phút | Trạng thái kênh + thời điểm cập nhật |
| `data/noi-dung.json` | **Admin sửa tay** | Link Launcher, link Game (Google Sheet), tin tức |
| `index.html`, `assets/` | Cố định | Giao diện |
| `scripts/Push-TrangThai.ps1` | — | Chạy trên VPS để đẩy trạng thái |

## Cài đặt lần đầu (làm 1 lần)

### 1. Tạo repo GitHub (public)
- Tạo repo mới, ví dụ `hknt-status`. Đẩy toàn bộ thư mục này lên nhánh `main`.

### 2. Bật GitHub Pages
- Repo → **Settings → Pages** → Source: `Deploy from a branch` → Branch `main` / `(root)` → Save.
- Vài phút sau có địa chỉ: `https://<tài-khoản>.github.io/hknt-status/`

### 3. Tạo token đẩy trạng thái + đặt vào biến môi trường
- GitHub → **Settings → Developer settings → Tokens**. Nên dùng **Fine-grained token**: chỉ repo này,
  quyền **Contents: Read and write** (blast radius nhỏ nhất). Token classic `repo` cũng chạy nhưng rộng hơn.
- Đặt vào **biến môi trường máy** trên VPS (không để trong repo):
  ```powershell
  [Environment]::SetEnvironmentVariable("HKNT_GH_TOKEN", "ghp_...", "Machine")
  ```
  Script đọc `HKNT_GH_TOKEN` trước; nếu trống mới đọc tệp `C:\HKServer\Secrets\github-status-push.token`.

### 4. Sửa cấu hình trong `scripts/Push-TrangThai.ps1`
- `$GitHubOwner`, `$GitHubRepo` cho khớp tài khoản/repo (đang đặt `5merchdtv-ux` / `NgaoThien`).
- `$K1Port` = cổng client Kênh 1 (mặc định `15001`; K2 = `15002`). Script chỉ mở 1 gói TCP để dò,
  **không đụng gameplay**, không phụ thuộc gateway.

### 5. Lên lịch chạy (Task Scheduler, mỗi 5 phút)
Chạy PowerShell (Admin) trên VPS:

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\Administrator\Downloads\HKNT_STATUS_SITE\scripts\Push-TrangThai.ps1"'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
  -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "HKNT-Push-TrangThai" -Action $action -Trigger $trigger `
  -RunLevel Highest -Description "Đẩy trạng thái kênh lên GitHub cho trang công khai"
```

Chạy thử ngay một lần để kiểm tra:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Administrator\Downloads\HKNT_STATUS_SITE\scripts\Push-TrangThai.ps1"
```

## Cập nhật tin tức / link tải (hằng ngày)

Sửa `data/noi-dung.json` rồi commit lên repo (sửa thẳng trên web GitHub cũng được):

- `linkGame`: link tải bản game (đang dùng link Google Drive). Launcher đã nằm trong bản game nên chỉ
  cần một nút "Tải Game".
- `tinTuc`: danh sách tin, mỗi tin có `ngay`, `tieuDe`, `noiDung`.

Site tự làm mới mỗi 5 phút; người xem F5 là thấy ngay.
