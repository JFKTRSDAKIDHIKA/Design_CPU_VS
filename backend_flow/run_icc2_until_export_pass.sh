#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT_DIR/logs"
MAIN_LOG="$LOG_DIR/icc2_pnr.log"
RUN_LOG="$LOG_DIR/icc2_pnr_autorun.log"
MAX_ITERS="${MAX_ITERS:-5}"

mkdir -p "$LOG_DIR"

export ICC2_FAST_DEBUG="${ICC2_FAST_DEBUG:-1}"

echo "INFO: ROOT_DIR=$ROOT_DIR" | tee "$RUN_LOG"
echo "INFO: ICC2_FAST_DEBUG=$ICC2_FAST_DEBUG" | tee -a "$RUN_LOG"
echo "INFO: MAX_ITERS=$MAX_ITERS" | tee -a "$RUN_LOG"

for iter in $(seq 1 "$MAX_ITERS"); do
  echo "INFO: === ICC2 attempt $iter/$MAX_ITERS ===" | tee -a "$RUN_LOG"

  if find "$ROOT_DIR" -type d -name '*.dlib' | grep -q .; then
    echo "INFO: Found existing .dlib libraries; current script still runs full flow, but saved blocks can be reused in future targeted recovery scripts." | tee -a "$RUN_LOG"
  else
    echo "INFO: No reusable .dlib checkpoint found; running flow from script start." | tee -a "$RUN_LOG"
  fi

  (
    cd "$ROOT_DIR"
    icc2_shell -f pnr_icc2.tcl | tee "$MAIN_LOG"
  ) || true

  if grep -q "INFO: 完成步骤 -> 导出结果" "$MAIN_LOG"; then
    echo "INFO: Export stage completed successfully." | tee -a "$RUN_LOG"
    exit 0
  fi

  echo "WARN: ICC2 did not complete export stage on attempt $iter." | tee -a "$RUN_LOG"
  echo "INFO: Last 160 log lines:" | tee -a "$RUN_LOG"
  tail -n 160 "$MAIN_LOG" | tee -a "$RUN_LOG"

  if ! grep -Eq "ERROR:|Error:|CMD-" "$MAIN_LOG"; then
    echo "WARN: No explicit command error found in log tail; stopping retry loop for manual inspection." | tee -a "$RUN_LOG"
    exit 1
  fi
done

echo "ERROR: ICC2 export stage did not pass after $MAX_ITERS attempts." | tee -a "$RUN_LOG"
exit 1
