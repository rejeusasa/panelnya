#!/bin/bash

################################################################################
# 🔧 SETUP CLOUDFLARE TUNNEL FOR PANEL
# Panel Tunnel: panel.jujulefek.qzz.io → localhost:7860
################################################################################

set -e

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║    🚀 PANEL CLOUDFLARE TUNNEL SETUP 🚀                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📋 STEP 1: Authenticate with Cloudflare"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Run: cloudflared tunnel login"
echo ""
read -p "Press ENTER after authentication... "

echo ""
echo "✅ STEP 2: Create Tunnel"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cloudflared tunnel create panel-service 2>/dev/null || echo "⚠️  Tunnel exists"
sleep 2

echo ""
echo "✅ STEP 3: Setup DNS Route"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cloudflared tunnel route dns panel-service panel.jujulefek.qzz.io
echo "[✓] DNS route configured"
sleep 2

echo ""
echo "✅ STEP 4: Create Tunnel Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ ! -f "$PROJECT_DIR/cloudflare-tunnel-config.yaml" ]; then
    cat > "$PROJECT_DIR/cloudflare-tunnel-config.yaml" << 'EOF'
tunnel: panel-service
credentials-file: /root/.cloudflared/cert.pem
logfile: /var/log/cloudflared/tunnel.log
loglevel: info

ingress:
  - hostname: panel.jujulefek.qzz.io
    service: http://localhost:7860
    originRequest:
      httpHostHeader: panel.jujulefek.qzz.io
  - service: http_status:404
EOF
    echo "[✓] cloudflare-tunnel-config.yaml created"
fi

echo ""
echo "✅ STEP 5: Verify Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cloudflared tunnel list
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    🎉 SETUP COMPLETE! 🎉                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Panel accessible at:"
echo "  🌐 https://panel.jujulefek.qzz.io"
echo ""
echo "Start tunnel:"
echo "  cloudflared tunnel run panel-service"
echo ""
