#!/bin/bash

################################################################################
# 🚀 PANEL SERVICE INSTALLATION SCRIPT
# Install dependencies & setup for Panel automation
# Connects to: dashboard.jujulefek.qzz.io
#
# Usage: chmod +x install-panel.sh && ./install-panel.sh
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

################################################################################
# SECTION 1: SYSTEM REQUIREMENTS CHECK
################################################################################
log_info "=== CHECKING SYSTEM REQUIREMENTS ==="

if [[ $EUID -ne 0 ]]; then
   log_warn "Script tidak dijalankan sebagai root. Beberapa instalasi mungkin membutuhkan sudo."
   USE_SUDO="sudo"
else
   USE_SUDO=""
fi

if ! [[ "$OSTYPE" == "linux-gnu"* ]]; then
    log_error "Script ini hanya support Linux. Detected: $OSTYPE"
    exit 1
fi
log_success "OS: Linux"

if ! command -v python3 &> /dev/null; then
    log_error "Python 3 tidak terinstall"
    exit 1
fi
log_success "Python 3: $(python3 --version)"

if ! command -v pip3 &> /dev/null; then
    log_error "pip3 tidak terinstall"
    exit 1
fi
log_success "pip3: $(pip3 --version)"

################################################################################
# SECTION 2: SETUP PROJECT DIRECTORY
################################################################################
log_info "=== SETTING UP PROJECT DIRECTORY ==="

PROJECT_DIR="${1:-.}"
VENV_DIR="${PROJECT_DIR}/venv"

cd "$PROJECT_DIR"
log_success "Working directory: $(pwd)"

if [ ! -d "$VENV_DIR" ]; then
    log_info "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    log_success "Virtual environment created"
else
    log_success "Virtual environment already exists"
fi

source "$VENV_DIR/bin/activate"
log_success "Virtual environment activated"

################################################################################
# SECTION 3: INSTALL PYTHON DEPENDENCIES
################################################################################
log_info "=== INSTALLING PYTHON DEPENDENCIES ==="

log_info "Upgrading pip, setuptools, wheel..."
pip install --upgrade pip setuptools wheel

log_info "Installing dependencies from requirements.txt..."
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    pip install -r "$PROJECT_DIR/requirements.txt"
    log_success "Dependencies installed"
else
    log_warn "requirements.txt not found, installing manually..."
    pip install flask flask-cors psutil requests urllib3 selenium pyautogui mss python-dotenv
fi

################################################################################
# SECTION 4: INSTALL SYSTEM PACKAGES
################################################################################
log_info "=== INSTALLING SYSTEM PACKAGES ==="

if ! command -v google-chrome &> /dev/null; then
    log_info "Installing Google Chrome..."
    $USE_SUDO apt-get update
    $USE_SUDO apt-get install -y google-chrome-stable
    log_success "Google Chrome installed"
else
    log_success "Google Chrome already installed"
fi

if ! command -v Xvfb &> /dev/null; then
    log_info "Installing Xvfb (virtual display)..."
    $USE_SUDO apt-get install -y xvfb
    log_success "Xvfb installed"
else
    log_success "Xvfb already installed"
fi

################################################################################
# SECTION 5: CREATE CONFIGURATION FILES
################################################################################
log_info "=== CREATING CONFIGURATION FILES ==="

if [ ! -f "$PROJECT_DIR/.env" ]; then
    log_info "Creating .env file..."
    cat > "$PROJECT_DIR/.env" << 'ENVEOF'
PANEL_PORT=7860
DASHBOARD_URL=http://localhost:7861
AUTH_KEY=GHOST_SECRET_2026
FLASK_ENV=production
FLASK_DEBUG=False
ENVEOF
    log_success ".env created"
else
    log_warn ".env already exists - skipping"
fi

################################################################################
# SECTION 6: CREATE LOGS DIRECTORY
################################################################################
log_info "=== CREATING LOGS DIRECTORY ==="
mkdir -p "$PROJECT_DIR/logs"
log_success "Logs directory ready"

################################################################################
# SECTION 7: CREATE SERVICE SCRIPTS
################################################################################
log_info "=== CREATING SERVICE SCRIPTS ==="

# start-panel.sh
if [ ! -f "$PROJECT_DIR/start-panel.sh" ]; then
    cat > "$PROJECT_DIR/start-panel.sh" << 'SCRIPTEOF'
#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$PROJECT_DIR/venv"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
source "$VENV_DIR/bin/activate"
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║            🚀 PANEL SERVICE STARTUP 🚀                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
pkill -f "python.*agent.py" || true
sleep 1
cd "$PROJECT_DIR"
echo "[✓] Starting Agent Panel on Port 7860..."
python agent.py > "$LOG_DIR/panel.log" 2>&1 &
echo "    URL: http://localhost:7860"
echo "    Dashboard: http://localhost:7861"
echo ""
echo "Monitor: tail -f $LOG_DIR/panel.log"
echo "Stop: ./stop-panel.sh"
echo ""
SCRIPTEOF
    chmod +x "$PROJECT_DIR/start-panel.sh"
    log_success "start-panel.sh created"
fi

# stop-panel.sh
if [ ! -f "$PROJECT_DIR/stop-panel.sh" ]; then
    cat > "$PROJECT_DIR/stop-panel.sh" << 'SCRIPTEOF'
#!/bin/bash
echo "🛑 Stopping Panel service..."
pkill -f "python.*agent.py" || echo "Panel not running"
pkill -f "python.*login.py" || echo "Login not running"
pkill -f "python.*loop.py" || echo "Loop not running"
pkill -f "chrome" || true
sleep 2
if ! pgrep -f "python.*agent.py" > /dev/null; then
    echo "[✓] Panel stopped successfully"
else
    echo "[!] Some processes may still be running"
fi
echo ""
SCRIPTEOF
    chmod +x "$PROJECT_DIR/stop-panel.sh"
    log_success "stop-panel.sh created"
fi

# monitor-panel.sh
if [ ! -f "$PROJECT_DIR/monitor-panel.sh" ]; then
    cat > "$PROJECT_DIR/monitor-panel.sh" << 'SCRIPTEOF'
#!/bin/bash
LOG_DIR="./logs"
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             🔍 PANEL MONITORING DASHBOARD 🔍              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📡 SERVICE STATUS:"
if netstat -tlnp 2>/dev/null | grep ":7860 " > /dev/null; then
    echo "[✓] Panel: RUNNING (Port 7860)"
else
    echo "[✗] Panel: NOT RUNNING"
fi
if pgrep -f "python.*login.py" > /dev/null; then
    echo "[✓] Login: RUNNING"
else
    echo "[!] Login: NOT RUNNING"
fi
if pgrep -f "python.*loop.py" > /dev/null; then
    echo "[✓] Loop: RUNNING"
else
    echo "[!] Loop: NOT RUNNING"
fi
echo ""
echo "📊 RECENT LOGS:"
if [ -f "$LOG_DIR/panel.log" ]; then
    tail -n 15 "$LOG_DIR/panel.log"
else
    echo "No logs yet"
fi
echo ""
SCRIPTEOF
    chmod +x "$PROJECT_DIR/monitor-panel.sh"
    log_success "monitor-panel.sh created"
fi

################################################################################
# SECTION 8: VERIFY INSTALLATION
################################################################################
log_info "=== VERIFYING INSTALLATION ==="

log_info "Checking required files..."
for file in agent.py login.py loop.py modul_bot.py; do
    if [ -f "$PROJECT_DIR/$file" ]; then
        log_success "Found: $file"
    else
        log_warn "Missing: $file"
    fi
done

################################################################################
# FINAL SUMMARY
################################################################################
log_info "=== INSTALLATION COMPLETE ==="

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║      🎉 PANEL INSTALLATION COMPLETE! 🎉                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Project: $PROJECT_DIR"
echo "🐍 Venv: $VENV_DIR"
echo ""
echo "⚙️  CONFIGURATION:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Panel Port: 7860"
echo "  Dashboard: http://localhost:7861 (or dashboard.jujulefek.qzz.io)"
echo "  Environment: .env"
echo ""
echo "🚀 QUICK START:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣  Make sure Dashboard is running:"
echo "    On Dashboard Server: ./start-services.sh"
echo ""
echo "2️⃣  Update configuration (if needed):"
echo "    nano .env"
echo "    Set DASHBOARD_URL to your dashboard server"
echo ""
echo "3️⃣  Start Panel:"
echo "    ./start-panel.sh"
echo ""
echo "4️⃣  Monitor Panel:"
echo "    ./monitor-panel.sh"
echo "    tail -f logs/panel.log"
echo ""
echo "5️⃣  Stop Panel:"
echo "    ./stop-panel.sh"
echo ""
echo "📊 Panel will send data to:"
echo "    DASHBOARD_URL/api/register"
echo "    DASHBOARD_URL/api/report"
echo "    DASHBOARD_URL/api/ack"
echo ""
echo "✅ Ready to connect to Dashboard!"
echo ""
