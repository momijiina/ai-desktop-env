#!/usr/bin/env bash
# 03_start_ai_desktop_env.sh
#
# PC再起動後に ai-desktop-env を起動し直すためのスクリプト。
# WSL Ubuntu側で実行する。
#
# 使い方:
#   cd ~/ai-desktop-env
#   bash 03_start_ai_desktop_env.sh

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

run_ignore_error() {
  echo "+ $*"
  "$@" 2>/dev/null || true
}

if ! command -v workshop >/dev/null 2>&1; then
  echo "error: workshop コマンドが見つかりません。"
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "error: PROJECT_DIR がありません: $PROJECT_DIR"
  exit 1
fi

cd "$PROJECT_DIR"

log "snap service を起動します"
run_ignore_error sudo snap start lxd
run_ignore_error sudo snap start workshop
run_ignore_error sudo snap restart workshop

log "Workshop状態を確認します"
if ! workshop info >/tmp/workshop-info.txt 2>&1; then
  echo "workshop info に失敗しました。launch を試します。"
  workshop launch "$WORKSHOP_NAME" --verbose --wait-on-error
else
  cat /tmp/workshop-info.txt || true

  if grep -q "status:[[:space:]]*waiting" /tmp/workshop-info.txt || grep -q "status:[[:space:]]*paused" /tmp/workshop-info.txt; then
    echo "waiting/paused 状態のため abort を試します。"
    run_ignore_error workshop refresh --abort "$WORKSHOP_NAME"
  fi

  if ! grep -q "status:[[:space:]]*ready" /tmp/workshop-info.txt; then
    echo "readyではないため launch を試します。"
    workshop launch "$WORKSHOP_NAME" --verbose --wait-on-error || true
  fi
fi

log "tunnelを接続します"
workshop connect "$WORKSHOP_NAME/system:novnc" "$WORKSHOP_NAME/novnc:novnc" 2>/dev/null || true
workshop connections --all || true

log "サンドボックス内のVNC/noVNCを起動します"

workshop shell "$WORKSHOP_NAME" <<EOS
set -e

mkdir -p "\$HOME/.vnc"

if [ ! -f "\$HOME/.vnc/xstartup" ]; then
cat > "\$HOME/.vnc/xstartup" <<'EOF'
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
EOF
chmod +x "\$HOME/.vnc/xstartup"
fi

vncserver -kill :${VNC_DISPLAY} 2>/dev/null || true
pkill -f websockify 2>/dev/null || true

if [ -f "\$HOME/.config/systemd/user/vncserver.service" ] && [ -f "\$HOME/.config/systemd/user/novnc.service" ]; then
  systemctl --user daemon-reload || true
  systemctl --user restart vncserver.service || true
  sleep 2
  systemctl --user restart novnc.service || true
else
  vncserver :${VNC_DISPLAY} -localhost yes -SecurityTypes None -geometry ${GEOMETRY} -depth 24
  nohup websockify --web=/usr/share/novnc/ 127.0.0.1:${NOVNC_PORT} 127.0.0.1:590${VNC_DISPLAY} > /tmp/novnc.log 2>&1 &
fi

sleep 2
if ! ss -lntp | grep -q "127.0.0.1:${NOVNC_PORT}"; then
  echo "systemd起動が不十分なため、手動起動にfallbackします。"
  vncserver -kill :${VNC_DISPLAY} 2>/dev/null || true
  pkill -f websockify 2>/dev/null || true
  vncserver :${VNC_DISPLAY} -localhost yes -SecurityTypes None -geometry ${GEOMETRY} -depth 24
  nohup websockify --web=/usr/share/novnc/ 127.0.0.1:${NOVNC_PORT} 127.0.0.1:590${VNC_DISPLAY} > /tmp/novnc.log 2>&1 &
fi

echo "--- sandbox ports ---"
ss -lntp | grep -E "590${VNC_DISPLAY}|${NOVNC_PORT}" || true

echo "--- sandbox curl ---"
curl -I --max-time 10 http://127.0.0.1:${NOVNC_PORT}/vnc.html || true
EOS

log "WSL側から疎通確認します"
set +e
curl -I --max-time 10 "http://127.0.0.1:${NOVNC_PORT}/vnc.html"
CURL_STATUS=$?
set -e

if [ "$CURL_STATUS" -eq 0 ]; then
  cat <<EOF

起動完了です。

ブラウザで開く:
  http://127.0.0.1:${NOVNC_PORT}/vnc.html?autoconnect=1&resize=scale

別PCから:
  http://WindowsPCのIPアドレス:${NOVNC_PORT}/vnc.html?autoconnect=1&resize=scale

EOF
else
  cat <<EOF

起動処理は実行しましたが、WSL側からnoVNCに接続できませんでした。

確認コマンド:
  cd "$PROJECT_DIR"
  workshop connections --all
  workshop shell "$WORKSHOP_NAME"
  systemctl --user status vncserver.service --no-pager -l
  systemctl --user status novnc.service --no-pager -l
  ss -lntp | grep -E '590${VNC_DISPLAY}|${NOVNC_PORT}'
  tail -n 100 ~/.vnc/*.log
  cat /tmp/novnc.log

EOF
fi
