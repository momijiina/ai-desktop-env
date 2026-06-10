#!/usr/bin/env bash
# 02_reset_ai_desktop_env.sh
#
# ai-desktop-env Workshopサンドボックスを削除して、必要なら再構築するスクリプト。
#
# 使い方:
#   bash 02_reset_ai_desktop_env.sh
#
# 環境変数:
#   WORKSHOP_NAME=ai-desktop-env
#   PROJECT_DIR=$HOME/ai-desktop-env
#   REBUILD=1                 # 1なら削除後に再構築する。0なら削除だけ。
#   BUILD_SCRIPT=01_wsl_build_ai_desktop_env.sh
#
# 例:
#   # 削除だけ
#   REBUILD=0 bash 02_reset_ai_desktop_env.sh
#
#   # 名前や場所を変える
#   WORKSHOP_NAME=ai-desktop-env PROJECT_DIR=~/ai-desktop-env bash 02_reset_ai_desktop_env.sh

set -euo pipefail

WORKSHOP_NAME="${WORKSHOP_NAME:-ai-desktop-env}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/ai-desktop-env}"
REBUILD="${REBUILD:-1}"
BUILD_SCRIPT="${BUILD_SCRIPT:-01_wsl_build_ai_desktop_env.sh}"

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
  echo "先に sudo snap install --classic workshop を実行してください。"
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "error: PROJECT_DIR がありません: $PROJECT_DIR"
  exit 1
fi

cd "$PROJECT_DIR"

log "現在の状態を確認します"
run_ignore_error workshop info
run_ignore_error workshop connections --all
run_ignore_error workshop tasks

log "paused / waiting 状態を解除します"
run_ignore_error workshop refresh --abort "$WORKSHOP_NAME"

log "tunnel接続を解除します"
run_ignore_error workshop disconnect "$WORKSHOP_NAME/system:novnc" "$WORKSHOP_NAME/novnc:novnc"

log "Workshop環境を停止します"
run_ignore_error workshop stop "$WORKSHOP_NAME"

log "Workshop環境を削除します"
# workshop remove が確認入力を求める環境に備えて yes を流す。
# 既に存在しない場合はエラーを無視する。
echo "+ yes | workshop remove $WORKSHOP_NAME"
yes | workshop remove "$WORKSHOP_NAME" 2>/dev/null || true

log "削除後の確認"
run_ignore_error workshop info
run_ignore_error workshop connections --all

if [ "$REBUILD" != "1" ]; then
  cat <<EOF

削除のみ完了しました。

再構築する場合は、以下を実行してください。

  cd "$PROJECT_DIR"
  bash "$BUILD_SCRIPT"

EOF
  exit 0
fi

log "再構築します"

if [ -f "$PROJECT_DIR/$BUILD_SCRIPT" ]; then
  echo "+ bash $BUILD_SCRIPT"
  bash "$PROJECT_DIR/$BUILD_SCRIPT"
else
  echo "build script が見つかりません: $PROJECT_DIR/$BUILD_SCRIPT"
  echo "既存の Workshop 定義から直接 launch を試します。"

  echo "+ workshop launch $WORKSHOP_NAME --verbose --wait-on-error"
  workshop launch "$WORKSHOP_NAME" --verbose --wait-on-error

  echo "+ workshop connect $WORKSHOP_NAME/system:novnc $WORKSHOP_NAME/novnc:novnc"
  workshop connect "$WORKSHOP_NAME/system:novnc" "$WORKSHOP_NAME/novnc:novnc" 2>/dev/null || true
fi

log "最終確認"
workshop connections --all || true

set +e
curl -I --max-time 10 http://127.0.0.1:6080/vnc.html
CURL_STATUS=$?
set -e

if [ "$CURL_STATUS" -eq 0 ]; then
  cat <<EOF

成功しました。

ブラウザで開く:

  http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale

EOF
else
  cat <<EOF

再構築は完了しましたが、noVNCへの疎通確認に失敗しました。

確認コマンド:

  cd "$PROJECT_DIR"
  workshop connections --all
  workshop shell "$WORKSHOP_NAME"
  systemctl --user status vncserver.service --no-pager -l
  systemctl --user status novnc.service --no-pager -l
  ss -lntp | grep -E '5901|6080'
  tail -n 100 ~/.vnc/*.log

EOF
fi
