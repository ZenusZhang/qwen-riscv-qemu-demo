#!/bin/sh
set -eu
export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}

MODEL_ARCHIVE=${MODEL_ARCHIVE:-/usr/local/share/qwen/qwen3_0_6b.ts.gz}
MODEL_TMP_DIR=${QWEN_TMPDIR:-/var/tmp/qwen}
PROMPT=${PROMPT_TOKENS:-/usr/local/share/qwen/prompt_tokens.txt}
OUTPUT=${1:-/tmp/qwen_output_tokens.txt}
MAX_NEW_TOKENS=${MAX_NEW_TOKENS:-1}
EOS_TOKEN=${EOS_TOKEN_ID:-151645}
PRESERVE_ARCHIVE=${PRESERVE_MODEL_ARCHIVE:-auto}
HOST_SHARE_PREFIX="/mnt/host/"

MODEL_BASENAME=${MODEL_ARCHIVE##*/}
MODEL_EXT=${MODEL_ARCHIVE##*.}
MODEL_STEM=${MODEL_BASENAME%.gz}

if [ "${QWEN_MODEL_PATH+x}" = x ]; then
  MODEL_PATH="$QWEN_MODEL_PATH"
else
  if [ "${MODEL_ARCHIVE#$HOST_SHARE_PREFIX}" != "$MODEL_ARCHIVE" ]; then
    if [ "$MODEL_EXT" = "gz" ]; then
      MODEL_PATH="${MODEL_ARCHIVE%.gz}"
    else
      MODEL_PATH="$MODEL_ARCHIVE"
    fi
  else
    if [ "$MODEL_EXT" = "gz" ]; then
      MODEL_PATH="$MODEL_TMP_DIR/$MODEL_STEM"
    else
      MODEL_PATH="$MODEL_TMP_DIR/$MODEL_BASENAME"
    fi
    case "$MODEL_PATH" in
      *.ts) ;;
      *) MODEL_PATH="${MODEL_PATH}.ts" ;;
    esac
  fi
fi

if [ ! -f "$PROMPT" ]; then
  echo "Prompt tokens not found at $PROMPT" >&2
  exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
  if [ ! -f "$MODEL_ARCHIVE" ]; then
    echo "Model source not found. Expected either $MODEL_PATH or $MODEL_ARCHIVE" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$MODEL_PATH")"
  echo "Staging Qwen3 0.6B model to $MODEL_PATH ..."

  if [ "$MODEL_EXT" = "gz" ]; then
    gzip -dc "$MODEL_ARCHIVE" > "$MODEL_PATH"
    REMOVE_ARCHIVE=0
    case "$PRESERVE_ARCHIVE" in
      1|true|TRUE|yes|YES) REMOVE_ARCHIVE=0 ;;
      *)
        if [ "${MODEL_ARCHIVE#$HOST_SHARE_PREFIX}" != "$MODEL_ARCHIVE" ]; then
          REMOVE_ARCHIVE=0
        else
          case "$MODEL_ARCHIVE" in
            /usr/local/share/qwen/*) REMOVE_ARCHIVE=1 ;;
          esac
        fi
        ;;
    esac
    if [ "$REMOVE_ARCHIVE" -eq 1 ]; then
      rm -f "$MODEL_ARCHIVE"
    fi
  else
    cp "$MODEL_ARCHIVE" "$MODEL_PATH"
  fi
fi

/usr/local/bin/qwen3_infer "$MODEL_PATH" "$PROMPT" "$OUTPUT" "$MAX_NEW_TOKENS" "$EOS_TOKEN"
printf 'Qwen output tokens written to %s\n' "$OUTPUT"
cat "$OUTPUT"
