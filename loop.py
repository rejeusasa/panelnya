from multiprocessing import Process, Manager
import os
import time
import sys
import json
import psutil # Library wajib untuk manajemen process di Docker

# Import modul bot (Pastikan modul_bot.py ada)
try:
    from modul_bot import worker, get_profiles_from_mapping, read_file_lines
except ImportError:
    print("❌ Error: modul_bot.py tidak ditemukan!")
    sys.exit(1)

# ==========================================
# ⚙️ KONFIGURASI
# ==========================================
STATUS_FILE = "monitor.json"
MAX_BATCH_TIME = 43200 # 12 Jam

# ==========================================
# 🛠️ UTILS (OPTIMIZED FOR DOCKER/HF)
# ==========================================
def force_kill_chrome():
    """
    Membersihkan Chrome/Chromedriver menggunakan psutil.
    Lebih aman untuk environment terbatas (Non-Root).
    """
    print("🧹 [CLEANUP] Scanning for stray Chrome processes...", flush=True)
    
    # Target nama process yang mau dibunuh
    targets = ['chrome', 'chromedriver', 'chromium', 'google-chrome']
    my_pid = os.getpid()
    
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            # Jangan bunuh diri sendiri
            if proc.pid == my_pid: continue
            
            # Cek apakah nama process ada di target
            if any(t in proc.info['name'].lower() for t in targets):
                try:
                    proc.terminate() # Coba matikan baik-baik
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
            
    # Tunggu sebentar agar resource lepas
    time.sleep(2)
    clean_zombies()

def clean_zombies():
    """
    Membersihkan process zombie (defunct).
    Sangat penting di Docker agar tabel process tidak penuh.
    """
    try:
        for proc in psutil.process_iter(['pid', 'status']):
            if proc.info['status'] == psutil.STATUS_ZOMBIE:
                try: 
                    proc.wait(timeout=0) # Reap the zombie
                except: 
                    pass
    except: pass

def save_status(status_dict, time_remaining):
    """
    Menyimpan status ke JSON (Atomic Write).
    """
    try:
        data = {
            "time_remaining": time_remaining,
            "workers": dict(status_dict)
        }
        with open(STATUS_FILE + ".tmp", "w") as f:
            json.dump(data, f)
        os.replace(STATUS_FILE + ".tmp", STATUS_FILE)
    except: pass

# ==========================================
# 🚀 MAIN LOOP PROCESS
# ==========================================
if __name__ == "__main__":
    BASE_DIR = os.getcwd()
    MAPPING_FILE = os.path.join(BASE_DIR, "mapping_profil.txt")
    LINK_FILE = os.path.join(BASE_DIR, "link.txt")
    
    # Bersihkan status lama
    if os.path.exists(STATUS_FILE): os.remove(STATUS_FILE)

    print("🚀 [LOOP] Service Started. Monitoring via 'monitor.json'", flush=True)

    with Manager() as manager:
        # Shared Dictionary untuk komunikasi antar proses
        status_dict = manager.dict()

        while True:
            # 1. Bersih-bersih awal
            force_kill_chrome()
            
            status_dict['SYSTEM'] = "Initializing Batch..."
            save_status(status_dict, MAX_BATCH_TIME)
            time.sleep(3) 

            # 2. Cek File Data
            if not os.path.exists(MAPPING_FILE) or not os.path.exists(LINK_FILE):
                status_dict['SYSTEM'] = "Waiting for Data Files..."
                save_status(status_dict, MAX_BATCH_TIME)
                time.sleep(10)
                continue

            user_profiles = get_profiles_from_mapping(MAPPING_FILE)
            all_links = read_file_lines(LINK_FILE)
            
            if not user_profiles or not all_links:
                status_dict['SYSTEM'] = "Data Empty (Profiles/Links Missing)"
                save_status(status_dict, MAX_BATCH_TIME)
                time.sleep(10)
                continue
            
            # 3. Bagi Tugas (Distribusi Link)
            status_dict['SYSTEM'] = "Running"
            for p in user_profiles:
                status_dict[p['name']] = "Idle (Waiting Queue)"

            links_for_profiles = [[] for _ in user_profiles]
            for i, link in enumerate(all_links):
                links_for_profiles[i % len(user_profiles)].append(link)
            
            processes = []

            print(f"🔄 [LOOP] Starting Batch: {len(user_profiles)} Workers | {len(all_links)} Links", flush=True)

            # 4. Jalankan Worker (Multiprocessing)
            for i, profile in enumerate(user_profiles):
                p = Process(target=worker, args=(
                    profile['name'],
                    profile['user_data_dir'],
                    profile['profile_dir'],
                    profile['window_position'],
                    links_for_profiles[i],
                    status_dict  # Worker update status kesini
                ))
                p.start()
                processes.append(p)
                time.sleep(1) 

            # 5. Monitoring Loop (Tunggu Batch Selesai)
            start_wait = time.time()
            
            while True:
                elapsed = int(time.time() - start_wait)
                sisa = MAX_BATCH_TIME - elapsed
                
                # Update JSON Status
                save_status(status_dict, sisa)
                
                # Cek Apakah Semua Worker Mati/Selesai
                if not any(p.is_alive() for p in processes):
                    status_dict['SYSTEM'] = "Batch Finished. Restarting..."
                    save_status(status_dict, 0)
                    print("✅ [LOOP] Batch Finished.", flush=True)
                    break
                
                # Cek Timeout (Mencegah Loop Nyangkut Selamanya)
                if elapsed > MAX_BATCH_TIME:
                    print(f"⚠️ [LOOP] Batch Timeout ({MAX_BATCH_TIME}s). Killing workers...", flush=True)
                    status_dict['SYSTEM'] = "Time Limit Reached."
                    save_status(status_dict, 0)
                    
                    # [PENTING] Cara mematikan worker yang benar di Docker:
                    for p in processes:
                        if p.is_alive():
                            try:
                                p.terminate() # Kirim sinyal berhenti
                                p.join(timeout=1) # Tunggu dia benar-benar mati (Hapus Zombie)
                                if p.is_alive():
                                    p.kill() # Kalau bandel, paksa bunuh
                            except: pass
                    break
                
                time.sleep(2) # Sleep 2 detik biar hemat CPU

            # 6. Istirahat sebelum batch baru
            # Kosongkan list process agar memory python bersih
            processes = [] 
            force_kill_chrome()
            time.sleep(5)