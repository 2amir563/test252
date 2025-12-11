#!/bin/bash
# Telegram Media Downloader Bot - Complete Installer (V23 - Persian/Farsi Localization)

set -e # در صورت بروز هر گونه خطا، نصب متوقف شود.

echo "=============================================="
echo "🤖 ربات دانلودر رسانه تلگرام - V23 (نصب کامل)"
echo "=============================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Helper functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check root access
if [ "$EUID" -ne 0 ]; then
    print_error "لطفاً اسکریپت را با دسترسی روت اجرا کنید: sudo bash install.sh"
    exit 1
fi

# Ask for bot token
echo "🔑 توکن ربات خود را از @BotFather وارد کنید:"
read -p "📝 توکن ربات: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "وارد کردن توکن ربات ضروری است!"
    exit 1
fi

print_status "شروع فرآیند نصب..."

# ============================================
# STEP 1: System Update & Essential Tools
# ============================================
print_status "به‌روزرسانی و نصب ابزارهای ضروری (Python3, PIP, FFmpeg)..."
apt-get update -y
apt-get install -y python3 python3-pip ffmpeg curl wget nano git

# Remove system's youtube-dl/yt-dlp to prevent conflicts
print_status "حذف بسته‌های yt-dlp/youtube-dl سیستمی..."
apt-get remove -y youtube-dl yt-dlp 2>/dev/null || true

# ============================================
# STEP 2: Create Project Structure
# ============================================
print_status "ایجاد ساختار دایرکتوری پروژه..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

mkdir -p downloads logs cookies tmp
chmod -R 777 downloads logs cookies tmp

# ============================================
# STEP 3: Install Python Packages (Core requirements only)
# ============================================
print_status "نصب/به‌روزرسانی yt-dlp و بسته‌های Python..."

cat > requirements.txt << 'REQEOF'
python-telegram-bot>=20.7
python-dotenv>=1.0.0
yt-dlp>=2024.4.9
aiofiles>=23.2.1
requests>=2.31.0
psutil>=5.9.8
REQEOF

python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

# ============================================
# STEP 4: Create Configuration (.env)
# ============================================
print_status "ایجاد فایل‌های پیکربندی..."

cat > .env << ENVEOF
BOT_TOKEN=${BOT_TOKEN}
MAX_FILE_SIZE=2000
DELETE_AFTER_MINUTES=2
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
ENVEOF

# ============================================
# STEP 5: Create Bot File (bot.py - V23 - Persian)
# ============================================
print_status "ایجاد فایل اصلی ربات (bot.py - V23)..."

cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - V23 (Persian - Title/URL in Caption)
"""

import os
import sys
import logging
import subprocess
import asyncio
import re
import json
from pathlib import Path
from datetime import datetime
from urllib.parse import urlparse, unquote

from telegram import Update
from telegram.ext import (
    Application, 
    CommandHandler, 
    MessageHandler, 
    filters, 
    ContextTypes
)
from telegram.constants import ParseMode
from dotenv import load_dotenv

# Load environment (Make sure .env file exists in the directory)
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
DELETE_AFTER = int(os.getenv("DELETE_AFTER_MINUTES", "2"))
MAX_SIZE_MB = int(os.getenv("MAX_FILE_SIZE", "2000"))
USER_AGENT = os.getenv("USER_AGENT", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

if not BOT_TOKEN:
    print("ERROR: BOT_TOKEN is missing in .env file.")
    sys.exit(1)

# Setup basic logging (minimal)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def clean_url(text):
    """Clean URL from text"""
    if not text:
        return None
    text = text.strip()
    url_pattern = r'(https?://[^\s<>"\']+|www\.[^\s<>"\']+\.[a-z]{2,})'
    matches = re.findall(url_pattern, text, re.IGNORECASE)
    if matches:
        url = matches[0]
        if not url.startswith(('http://', 'https://')):
            url = 'https://' + url
        url = re.sub(r'[.,;:!?]+$', '', url)
        return unquote(url)
    return None

def format_size(bytes_val):
    """Format file size"""
    if bytes_val is None:
        return "نامشخص"
    try:
        bytes_val = float(bytes_val)
        for unit in ['بایت', 'کیلوبایت', 'مگابایت', 'گیگابایت']:
            if bytes_val < 1024.0:
                return f"{bytes_val:.1f} {unit}"
            bytes_val /= 1024.0
        return f"{bytes_val:.1f} ترابایت"
    except:
        return "نامشخص"

async def get_video_info(url):
    """Fetch video title using yt-dlp --dump-json"""
    cmd = [
        "python3", "-m", "yt_dlp",
        "--dump-json",
        "--skip-download",
        "--no-playlist",
        "--ignore-errors",
        "--user-agent", USER_AGENT,
        url
    ]
    cookies_file = Path(os.getcwd()) / "cookies" / "cookies.txt"
    if cookies_file.exists():
        cmd.extend(["--cookies", str(cookies_file)])
        
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        stdout, _ = await asyncio.wait_for(process.communicate(), timeout=30) 
        
        if process.returncode == 0:
            info = json.loads(stdout.decode('utf-8'))
            return info.get('title', 'N/A')
        
    except Exception as e:
        logger.error(f"Error fetching video info: {e}")
        
    return "N/A" # Return N/A if info fetching fails

async def download_video(url, output_path):
    """Core download logic"""
    
    download_format = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
    
    cmd = [
        "python3", "-m", "yt_dlp",
        "-f", download_format, 
        "-o", output_path,
        "--no-warnings",
        "--ignore-errors",
        "--no-playlist",
        "--concurrent-fragments", "4",
        "--limit-rate", "10M",
        "--retries", "5",               
        "--fragment-retries", "5",      
        "--buffer-size", "64K",         
        "--user-agent", USER_AGENT, 
        "--no-check-certificate", 
        "--referer", "https://google.com/",
        "--http-chunk-size", "10M",
        "--force-overwrite",
        url
    ]
    
    cookies_file = Path(os.getcwd()) / "cookies" / "cookies.txt"
    if cookies_file.exists():
        cmd.extend(["--cookies", str(cookies_file)])
    
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=480) 
        
        if process.returncode == 0:
            return True, "Success"
        else:
            return False, f"دانلود ناموفق: URL، دسترسی، یا محدودیت جغرافیایی را بررسی کنید."
            
    except asyncio.TimeoutError:
        return False, "اتمام زمان دانلود (8 دقیقه)."
    except Exception as e:
        return False, f"خطای داخلی: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = f"""
🤖 *ربات دانلودر رسانه جهانی - V23*

📝 *نحوه استفاده:*
1. هر URL ویدیویی را ارسال کنید.
2. ربات ویدیو را دانلود و همراه با عنوان اصلی برای شما ارسال می‌کند.
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages"""
    original_url = update.message.text
    url = clean_url(original_url)
    
    if not url:
        await update.message.reply_text("❌ *URL نامعتبر*", parse_mode=ParseMode.MARKDOWN)
        return
    
    # 1. Fetch Title 
    msg = await update.message.reply_text(f"🔗 *در حال پردازش URL...*\n\nدر حال دریافت جزئیات ویدیو...", parse_mode=ParseMode.MARKDOWN)
    video_title = await get_video_info(url)
    
    # Extract site name for filename
    try:
        parsed = urlparse(url)
        site = parsed.netloc.split('.')[-2] if parsed.netloc.count('.') >= 2 else parsed.netloc.split('.')[0]
        site = site.replace('www.', '').split(':')[0].upper()
    except:
        site = "UNKNOWN"
        
    await msg.edit_text(f"📥 *در حال دانلود...* (عنوان: {video_title[:50]}...)", parse_mode=ParseMode.MARKDOWN)
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{site}_{timestamp}"
    output_template = f"downloads/{filename}.%(ext)s"
    
    success, result = await download_video(url, output_template)
    
    if not success:
        await msg.edit_text(f"❌ *دانلود ناموفق*\n\nخطا: `{result}`", parse_mode=ParseMode.MARKDOWN)
        return
    
    # Find downloaded file
    downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
    downloaded_files.sort(key=lambda p: p.stat().st_size, reverse=True)
    
    if not downloaded_files:
        await msg.edit_text("❌ دانلود تکمیل شد اما فایل نهایی پیدا نشد.", parse_mode=ParseMode.MARKDOWN)
        return
    
    file_path = downloaded_files[0]
    file_size = file_path.stat().st_size
    
    if file_size > (MAX_SIZE_MB * 1024 * 1024):
        file_path.unlink() 
        await msg.edit_text(f"❌ *حجم فایل بیش از حد مجاز است:* {format_size(file_size)}", parse_mode=ParseMode.MARKDOWN)
        return
    
    await msg.edit_text(f"📤 *در حال آپلود...*\n\nحجم: {format_size(file_size)}", parse_mode=ParseMode.MARKDOWN)
    
    try:
        with open(file_path, 'rb') as file:
            file_ext = file_path.suffix.lower()
            
            # Custom Caption Format (Title, Size, URL)
            caption_text = (
                f"**{video_title}**\n\n"
                f"✅ دانلود تکمیل شد!\n"
                f"حجم: {format_size(file_size)}\n"
                f"لینک اصلی: [لینک]({url})"
            )
            
            # Simplified media type detection
            if file_ext in ['.mp3', '.m4a', '.wav']:
                await update.message.reply_audio(audio=file, caption=caption_text, parse_mode=ParseMode.MARKDOWN)
            else: 
                await update.message.reply_video(
                    video=file, 
                    caption=caption_text, 
                    parse_mode=ParseMode.MARKDOWN,
                    supports_streaming=True
                )
        
        await msg.edit_text("🎉 *موفقیت‌آمیز!*", parse_mode=ParseMode.MARKDOWN)
        
        # Auto delete after delay (Simplified)
        async def delete_file_task():
            await asyncio.sleep(DELETE_AFTER * 60)
            if file_path.exists():
                try:
                    file_path.unlink()
                except Exception:
                    pass
        asyncio.create_task(delete_file_task())
        
    except Exception as upload_error:
        await msg.edit_text(f"❌ *آپلود ناموفق*\n\nخطا: {str(upload_error)[:100]}", parse_mode=ParseMode.MARKDOWN)

def main():
    if not os.access(__file__, os.X_OK):
        try:
            os.chmod(__file__, 0o755) 
        except Exception:
            pass
            
    app = Application.builder().token(BOT_TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    
    try:
        print("✅ ربات شروع به نظرسنجی کرد...")
        app.run_polling(drop_pending_updates=True)
    except Exception as e:
        print(f"Bot failed to start polling: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYEOF

chmod +x bot.py

# ============================================
# STEP 6: Create Systemd Service (Start-up on reboot)
# ============================================
print_status "ایجاد سرویس systemd برای اجرای دائمی..."
PYTHON_PATH=$(which python3)

cat > /etc/systemd/system/telegram-media-bot.service << SERVICEEOF
[Unit]
Description=Telegram Media Downloader Bot
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=10
User=root
WorkingDirectory=/opt/telegram-media-bot
ExecStart=${PYTHON_PATH} /opt/telegram-media-bot/bot.py
StandardOutput=append:/opt/telegram-media-bot/logs/bot.log
StandardError=append:/opt/telegram-media-bot/logs/bot-error.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable telegram-media-bot.service

# ============================================
# STEP 7: Start Service
# ============================================
print_status "شروع سرویس ربات..."
systemctl start telegram-media-bot.service
sleep 3

# ============================================
# STEP 8: Show Final Instructions and COOKIE GUIDE (Persian)
# ============================================
echo ""
echo "================================================"
echo "🎉 نصب تکمیل شد (V23 - موفقیت‌آمیز)"
echo "================================================"
echo "💡 ربات شما در حال اجرا است. برای رفع خطاهای 'نیاز به ورود' (مانند برخی لینک‌های Streamable یا Pinterest)، از راهنمای کوکی استفاده کنید."
echo ""
echo "⚙️ دستورات کنترل:"
echo "------------------------------------------------"
echo "A) وضعیت سرویس:"
echo "   systemctl status telegram-media-bot"
echo "B) راه‌اندازی مجدد ربات (پس از قرار دادن کوکی‌ها ضروری است):"
echo "   systemctl restart telegram-media-bot"
echo "------------------------------------------------"
echo ""
echo "🍪 راهنمای تنظیم کوکی‌ها 🍪"
echo "------------------------------------------------"
echo "1. نصب افزونه مرورگر:"
echo "   افزونه 'Get cookies.txt' را برای مرورگر خود (Chrome/Edge/Brave) نصب کنید." 
echo "2. دریافت کوکی‌ها:"
echo "   به وب‌سایت دارای مشکل (مانند Streamable یا Bilibili) بروید و وارد حساب کاربری خود شوید."
echo "   روی آیکون افزونه کلیک کنید تا فایل 'cookies.txt' دانلود شود."
echo "3. انتقال فایل به سرور (با استفاده از SCP/WinSCP):"
echo "   فایل 'cookies.txt' دانلود شده را دقیقاً به این مسیر در سرور خود آپلود کنید:"
echo "   /opt/telegram-media-bot/cookies/cookies.txt"
echo "4. راه‌اندازی مجدد ربات:"
echo "   دستور راه‌اندازی مجدد (B) را اجرا کنید تا کوکی‌های جدید بارگذاری شوند."
echo ""
echo "این روش باید مشکلات دسترسی به لینک‌های محدود را حل کند."
echo "================================================"
