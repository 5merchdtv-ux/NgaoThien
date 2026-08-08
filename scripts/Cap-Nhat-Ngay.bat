@echo off
chcp 65001 >nul
title Cap nhat trang web NGAY
echo ============================================
echo   DANG CAP NHAT DU LIEU LEN WEB (NgaoThien)
echo   Trang thai / BXH / Cuong hoa / Tin tuc
echo ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Administrator\Downloads\HKNT_STATUS_SITE\scripts\Push-TrangThai.ps1"
echo.
echo ============================================
echo   XONG. Web se cap nhat sau ~1 phut (Pages build).
echo   Nhan phim bat ky de dong cua so nay.
echo ============================================
pause >nul
