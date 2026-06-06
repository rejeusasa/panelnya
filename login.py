import os
import time
import subprocess
import sys
import requests
import json
import pyautogui 
import mss 
import socket
import urllib3
import psutil 
from urllib.parse import urlparse

# ==========================================
# ⚙️ KONFIGURASI & BRIDGE SPESIFIK
# ==========================================
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

old_getaddrinfo = socket.getaddrinfo
DNS_MAP = {} 
TARGET_DOMAINS = ["api.ipify.org"]

def resolve_specific_domains():
    print("Bridge active for IP Check...", flush=True)
    for domain in TARGET_DOMAINS:
        try:
            api_url = f"https://dns.google/resolve?name={domain}"
            resp = requests.get(api_url, timeout=10, verify=False)
            data = resp.json()
            if 'Answer' in data:
                ip_address = data['Answer'][0]['data']
                DNS_MAP[domain] = ip_address
        except Exception as e:
            pass

def new_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    if host in DNS_MAP:
        return old_getaddrinfo(DNS_MAP[host], port, family, type, proto, flags)
    return old_getaddrinfo(host, port, family, type, proto, flags)

socket.getaddrinfo = new_getaddrinfo
resolve_specific_domains()

# ==========================================
# ⚙️ KONFIGURASI BOT
# ==========================================
PASSWORD = "Henstyle56"      
PROFILE_PREFIX = "dotaja"     
START_INDEX = 1               

SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
CHROME_PATH = "/usr/bin/google-chrome" 

BASE_PATH = os.getcwd() 
BASE_PROFILE_DIR = os.path.join(BASE_PATH, "chrome_profiles")
EMAIL_FILE = os.path.join(BASE_PATH, "email.txt")
MAPPING_FILE = os.path.join(BASE_PATH, "mapping_profil.txt")
HISTORY_FILE = os.path.join(BASE_PATH, "history_sukses.txt") 

# ==========================================
# CEK IP
# ==========================================
try:
    MY_IP = requests.get('https://api.ipify.org', timeout=15, verify=False).text.strip()
except:
    MY_IP = "Unknown IP"

# ==========================================
# FUNGSI PENDUKUNG
# ==========================================
def load_history():
    if not os.path.exists(HISTORY_FILE): return set()
    with open(HISTORY_FILE, "r") as f:
        return set(line.strip() for line in f if line.strip())

def save_history(email):
    with open(HISTORY_FILE, "a") as f:
        f.write(email + "\n")

def save_mapping(full_path, profile_name):
    if os.path.exists(MAPPING_FILE):
        with open(MAPPING_FILE, "r") as f:
            if any(full_path in line for line in f): return
    with open(MAPPING_FILE, "a") as f:
        f.write(f"{full_path}|{profile_name}\n")

def fix_crash_restore_popup(profile_path):
    pref_file = os.path.join(profile_path, "Default", "Preferences")
    if not os.path.exists(pref_file): return
    try:
        with open(pref_file, "r", encoding="utf-8") as f: data = json.load(f)
        if "profile" in data:
            data["profile"]["exit_type"] = "Normal"
            data["profile"]["exited_cleanly"] = True
            with open(pref_file, "w", encoding="utf-8") as f: json.dump(data, f)
    except: pass

# FUNGSI DINONAKTIFKAN TOTAL
def send_telegram_photo(caption, image_path):
    pass

def kill_chrome(proc_instance=None):
    if proc_instance:
        try:
            proc_instance.terminate()
            proc_instance.wait(timeout=2)
        except: pass

    my_pid = os.getpid()
    for p in psutil.process_iter(['name', 'cmdline']):
        try:
            if p.pid == my_pid: continue
            name = p.info['name'].lower()
            cmd = ' '.join(p.info['cmdline']) if p.info['cmdline'] else ''
            if 'chrome' in name or 'chrome' in cmd:
                try: p.terminate()
                except: pass
        except: pass
    time.sleep(1)

# ==========================================
# MAIN EXECUTION
# ==========================================
if not os.path.exists(EMAIL_FILE): 
    sys.exit(1)

with open(EMAIL_FILE, "r") as f:
    EMAILS = [line.strip() for line in f if line.strip()]

COMPLETED_EMAILS = load_history()
kill_chrome()

for i, EMAIL in enumerate(EMAILS, start=START_INDEX):
    folder_name = f"{PROFILE_PREFIX}{i:02d}"
    full_profile_path = os.path.join(BASE_PROFILE_DIR, folder_name)
    
    if not os.path.exists(full_profile_path): os.makedirs(full_profile_path)
    save_mapping(full_profile_path, folder_name)
    fix_crash_restore_popup(full_profile_path)

    if EMAIL in COMPLETED_EMAILS:
        MODE = "CHECK"
        TARGET_URL = "https://idx.google.com/joko" 
    else:
        MODE = "LOGIN"
        TARGET_URL = "https://idx.google.com/joko" 

    cmd = [
        CHROME_PATH, 
        "--no-sandbox", "--disable-dev-shm-usage", "--start-maximized",
        "--test-type",
        "--simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT'",
        "--disable-component-update",
        "--disable-session-crashed-bubble",
        "--no-first-run", "--no-default-browser-check", 
        f"--window-size={SCREEN_WIDTH},{SCREEN_HEIGHT}",
        f"--user-data-dir={full_profile_path}", 
        TARGET_URL
    ]
    
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_time = 15 if MODE == "LOGIN" else 10
    time.sleep(wait_time)

    try:
        if MODE == "LOGIN":
            pyautogui.write(EMAIL, interval=0.1)
            pyautogui.press("enter")
            time.sleep(8) 
            pyautogui.write(PASSWORD, interval=0.1)
            pyautogui.press("enter")
            time.sleep(15)
            save_history(EMAIL)
        
        # PROSES SIMPAN GAMBAR LOKAL
        ss_path = os.path.join(BASE_PATH, f"bukti_{folder_name}.png")
        try:
            with mss.mss() as sct: sct.shot(mon=-1, output=ss_path)
            print(f"Screenshot saved: {ss_path}", flush=True)
        except: pass

        # Tidak ada lagi pemanggilan Telegram di sini
            
    except Exception as e:
        print(f"Error: {e}")

    kill_chrome(proc)
    time.sleep(2)

print(f"Process Complete. IP: {MY_IP}")