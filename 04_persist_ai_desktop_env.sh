#!/usr/bin/env bash
# 04_persist_ai_desktop_env.sh
#
# ai-desktop-env の「起動コマンド」をWSL側に永続化するスクリプト。
#
# 前提:
# - ~/ai-desktop-env/03_start_ai_desktop_env.sh が存在すること
#
# 使い方:
#   cd ~/ai-desktop-env
#   bash 04_persist_ai_desktop_env.sh
#
# 環境変数:
#   PROJECT_DIR=$HOME/ai-desktop-env
#   START_SCRIPT=03_start_ai_desktop_env.sh
#   SERVICE_NAME=ai-desktop-env-start.service

set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/ai-desktop-env}"
START_SCRIPT="${START_SCRIPT:-03_start_ai_desktop_env.sh}"
SERVICE_NAME="${SERVICE_NAME:-ai-desktop-env-start.service}"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_PATH="$SERVICE_DIR/$SERVICE_NAME"

log() {
  echo
  echo "============================================================"
  echo "$*"
  echo "============================================================"
}

if [ ! -d "$PROJECT_DIR" ]; then
  echo "error: PROJECT_DIR がありません: $PROJECT_DIR"
  exit 1
fi

if [ ! -f "$PROJECT_DIR/$START_SCRIPT" ]; then
  echo "error: 起動スクリプトがありません: $PROJECT_DIR/$START_SCRIPT"
  echo
  echo "確認してください:"
  echo "  ls -la $PROJECT_DIR"
  echo
  echo "別名の場合は START_SCRIPT=ファイル名 を指定できます。"
  echo "例:"
  echo "  START_SCRIPT=03_start_ai_desktop_env.sh bash 04_persist_ai_desktop_env.sh"
  exit 1
fi

chmod +x "$PROJECT_DIR/$START_SCRIPT"

log "systemd user service を作成します"

mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Start AI Desktop Env Workshop/noVNC
After=default.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/bash $PROJECT_DIR/$START_SCRIPT
RemainAfterExit=yes
TimeoutStartSec=300

[Install]
WantedBy=default.target
EOF

log "systemd user service を有効化します"

systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"

log "試しに起動します"

set +e
systemctl --user start "$SERVICE_NAME"
STATUS=$?
set -e

echo
systemctl --user status "$SERVICE_NAME" --no-pager -l || true

if [ "$STATUS" -ne 0 ]; then
  cat <<EOF

[注意]
service の起動に失敗しました。

確認コマンド:
  journalctl --user -u $SERVICE_NAME -n 100 --no-pager
  cd "$PROJECT_DIR"
  bash "$START_SCRIPT"

EOF
  exit "$STATUS"
fi

cat <<EOF

永続化設定が完了しました。

WSL内で自動起動させる service:
  $SERVICE_NAME

実行される起動スクリプト:
  $PROJECT_DIR/$START_SCRIPT

状態確認:
  systemctl --user status $SERVICE_NAME --no-pager -l

ログ確認:
  journalctl --user -u $SERVICE_NAME -n 100 --no-pager

手動起動:
  systemctl --user start $SERVICE_NAME

無効化:
  systemctl --user disable --now $SERVICE_NAME

ブラウザ:
  http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale

ただし、Windows再起動直後にWSL自体を自動起動したい場合は、
04_persist_ai_desktop_env_windows.ps1 でWindowsタスクスケジューラ登録を行ってください。

EOF
