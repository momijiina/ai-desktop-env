#!/usr/bin/env bash
# 01_wsl_build_ai_desktop_env.sh
# WSL Ubuntu側で実行する自動構築スクリプト。
#
# 目的:
# - snapd / LXD / Workshop を導入
# - Workshop project を作成
# - Xfce Desktop + VNC + noVNC + Chromium + 日本語フォント環境を構築
# - tunnel を接続
#
# 実行例:
#   bash 01_wsl_build_ai_desktop_env.sh
#
# 注意:
# 初回実行時に lxd グループ追加後、WSL再起動が必要になる場合があります。
# その場合は表示に従って PowerShell で wsl --shutdown 後、再度このスクリプトを実行してください。

set -euo pipefail

WORKSHOP_NAME="${WORKSHOP_NAME:-ai-desktop-env}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/ai-desktop-env}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
GEOMETRY="${GEOMETRY:-1280x800}"

log() {
  echo
  echo "============================================================"
  echo "$*"
  echo "============================================================"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log "基本パッケージをインストールします"
sudo apt-get update
sudo apt-get install -y \
  snapd \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  software-properties-common

log "LXD / Workshop snap をインストールします"
if ! snap list lxd >/dev/null 2>&1; then
  sudo snap install --channel=6/stable lxd
else
  echo "lxd snap はインストール済みです"
fi

if ! snap list workshop >/dev/null 2>&1; then
  sudo snap install --classic workshop
else
  echo "workshop snap はインストール済みです"
fi

sudo snap start lxd >/dev/null 2>&1 || true
sudo snap start workshop >/dev/null 2>&1 || true

log "LXDを初期化します"
# 既に初期化済みの場合は失敗することがあるので続行。
sudo lxd init --auto || true

log "ユーザーを lxd グループへ追加します"
sudo usermod -aG lxd "$USER" || true

if ! id -nG "$USER" | tr ' ' '\n' | grep -qx "lxd"; then
  cat <<EOF

[重要]
現在のシェルでは lxd グループがまだ有効ではありません。

Windows側PowerShellで以下を実行してください。

  wsl --shutdown

その後、Ubuntuを開き直して、もう一度このスクリプトを実行してください。

EOF
  exit 20
fi

log "プロジェクトファイルを作成します: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR/.workshop/novnc/hooks"
cd "$PROJECT_DIR"

cat > .workshop/ai-desktop-env.yaml <<EOF
name: ${WORKSHOP_NAME}
base: ubuntu@24.04

sdks:
  - name: project-novnc
  - name: system
    plugs:
      novnc:
        interface: tunnel
        endpoint: 0.0.0.0:${NOVNC_PORT}/tcp
EOF

cat > .workshop/novnc/sdk.yaml <<EOF
name: novnc
version: "0.1"
summary: Browser-accessible desktop with noVNC
description: Provides a VNC session over noVNC.
license: MIT
base: ubuntu@24.04

platforms:
  amd64:
    build-on: [amd64]
    build-for: [amd64]

slots:
  novnc:
    interface: tunnel
    endpoint: 127.0.0.1:${NOVNC_PORT}/tcp
EOF

cat > .workshop/novnc/hooks/setup-base <<'EOF'
#!/bin/bash
set -eux

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  xfce4 \
  xfce4-session \
  xfce4-panel \
  xfdesktop4 \
  xfce4-terminal \
  dbus-x11 \
  xinit \
  x11-xserver-utils \
  tigervnc-standalone-server \
  tigervnc-common \
  novnc \
  websockify \
  xterm \
  language-pack-ja \
  locales \
  fonts-noto-cjk \
  fonts-noto-color-emoji \
  fonts-ipafont-gothic \
  fonts-ipafont-mincho \
  software-properties-common \
  xdg-utils \
  curl \
  ca-certificates

locale-gen ja_JP.UTF-8 || true
update-locale LANG=ja_JP.UTF-8 LANGUAGE=ja_JP:ja || true
fc-cache -fv || true

# ChromiumをPPA版で導入する。
# Ubuntu標準のchromiumはSnapへ寄ることがあり、Workshop/LXD内では扱いにくいことがあるため。
# PPA追加やChromium導入に失敗しても、デスクトップ構築自体は継続する。
if command -v add-apt-repository >/dev/null 2>&1; then
  if add-apt-repository -y ppa:xtradeb/apps; then
    apt-get update
    apt-get install -y chromium || true
  fi
fi
EOF

chmod +x .workshop/novnc/hooks/setup-base

cat > .workshop/novnc/hooks/setup-project <<EOF
#!/bin/bash
set -eux

mkdir -p "\$HOME/.vnc"
mkdir -p "\$HOME/.config/systemd/user"

cat > "\$HOME/.vnc/xstartup" <<'EOS'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export LANG=ja_JP.UTF-8
export LANGUAGE=ja_JP:ja
export LC_CTYPE=ja_JP.UTF-8

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
export XKL_XMODMAP_DISABLE=1

exec dbus-launch --exit-with-session startxfce4
EOS

chmod +x "\$HOME/.vnc/xstartup"

cat > "\$HOME/.config/systemd/user/vncserver.service" <<EOS
[Unit]
Description=TigerVNC server for Workshop desktop
After=default.target

[Service]
Type=forking
ExecStartPre=-/usr/bin/vncserver -kill :${VNC_DISPLAY}
ExecStart=/usr/bin/vncserver :${VNC_DISPLAY} -localhost yes -SecurityTypes None -geometry ${GEOMETRY} -depth 24
ExecStop=/usr/bin/vncserver -kill :${VNC_DISPLAY}
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOS

cat > "\$HOME/.config/systemd/user/novnc.service" <<EOS
[Unit]
Description=noVNC web proxy for Workshop desktop
After=vncserver.service
Requires=vncserver.service

[Service]
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ 127.0.0.1:${NOVNC_PORT} 127.0.0.1:590${VNC_DISPLAY}
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOS

# Chromiumを既定ブラウザに設定。失敗しても構築は続行。
if [ -f /usr/share/applications/chromium.desktop ]; then
  xdg-mime default chromium.desktop x-scheme-handler/http || true
  xdg-mime default chromium.desktop x-scheme-handler/https || true
  xdg-mime default chromium.desktop text/html || true
  xdg-settings set default-web-browser chromium.desktop || true
fi

systemctl --user daemon-reload
systemctl --user enable vncserver.service
systemctl --user enable novnc.service

# 起動に失敗した場合はhook全体を落として原因を見えるようにする。
systemctl --user restart vncserver.service
sleep 2
systemctl --user restart novnc.service
EOF

chmod +x .workshop/novnc/hooks/setup-project

log "Workshopを起動または更新します"
if workshop info 2>/dev/null | grep -q "name:[[:space:]]*${WORKSHOP_NAME}"; then
  echo "既存Workshopを更新します"
  if ! workshop refresh --verbose --wait-on-error; then
    echo "refreshが失敗しました。pausedの場合はabortして再試行します。"
    workshop refresh --abort "$WORKSHOP_NAME" || true
    workshop refresh --verbose --wait-on-error
  fi
else
  echo "Workshopを新規起動します"
  workshop launch "$WORKSHOP_NAME" --verbose --wait-on-error
fi

log "tunnelを接続します"
workshop connect "${WORKSHOP_NAME}/system:novnc" "${WORKSHOP_NAME}/novnc:novnc" 2>/dev/null || true
workshop connections --all

log "疎通確認します"
set +e
curl -I --max-time 10 "http://127.0.0.1:${NOVNC_PORT}/vnc.html"
CURL_STATUS=$?
set -e

if [ "$CURL_STATUS" -ne 0 ]; then
  cat <<EOF

[注意]
WSL本体側から http://127.0.0.1:${NOVNC_PORT}/vnc.html へ到達できませんでした。

確認コマンド:

  workshop connections --all
  workshop shell ${WORKSHOP_NAME}
  systemctl --user status vncserver.service --no-pager -l
  systemctl --user status novnc.service --no-pager -l
  ss -lntp | grep -E '5901|${NOVNC_PORT}'
  tail -n 100 ~/.vnc/*.log

EOF
else
  cat <<EOF

[成功]
noVNCに到達できました。

ブラウザで開く:

  http://127.0.0.1:${NOVNC_PORT}/vnc.html?autoconnect=1&resize=scale

別PCから開く場合:

  http://WindowsPCのIPアドレス:${NOVNC_PORT}/vnc.html?autoconnect=1&resize=scale

EOF
fi

log "完了"
