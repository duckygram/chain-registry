#!/bin/bash
#
# The script removes stale Terraform locks found in DynamoDB table with hardcoded name
# made my 'mate' user which is expected to run Gitlab CICD plan/apply jobs
#
# Run with '--dry' to test without actual removing of locks
#
# Most parameters are hardcoded, see below

APPLY_LOCK_TIMEOUT_SECS=3600
OTHER_LOCK_TIMEOUT_SECS=1800
BAD_LOCKS_OWNER=mate
LOCK_TABLE_NAME=

# decode cmdline args
DRY_RUN=
for arg in "$@"
do
  case $arg in
    --dry)
        DRY_RUN=1
        shift
        ;;
    --lock-table-name)
        shift;
        LOCK_TABLE_NAME="$1"
        shift;
        ;;
    *)
        OTHER_ARGUMENTS+=("$1")
        shift # Remove generic argument from processing
        ;;
    esac
done

set -e -o pipefail

[ "$LOCK_TABLE_NAME" ] || { echo "--lock-table-name is required"; exit 1; }

[ "$DRY_RUN" ] && echo "Running in DRY run mode"
locks_found=

for lock_json in $(aws dynamodb scan --consistent-read --table-name $LOCK_TABLE_NAME --query "Items[].Info"|jq '.[].S')
do
  lock_data=$(echo "$lock_json" | jq -r 'fromjson | "\(.Path) \(.ID) \(.Operation) \(.Created) \(.Who)"')
  read LOCK_KEY LOCK_ID LOCK_OP LOCK_TIME LOCK_HOLDER <<<"$lock_data"

  echo $lock_data
  lock_ts=$(date -d "$LOCK_TIME" +%s)
  now_ts=$(date +%s)
  lock_age_secs=$((now_ts - lock_ts))

  if [[ "$LOCK_HOLDER" =~ ^"$BAD_LOCKS_OWNER"@ ]]; then

    LOCK_TIMEOUT_SECS="$OTHER_LOCK_TIMEOUT_SECS"
    [ "$LOCK_OP" = "OperationTypeApply" ] && LOCK_TIMEOUT_SECS="$APPLY_LOCK_TIMEOUT_SECS"

    if [ "$lock_age_secs" -gt "$LOCK_TIMEOUT_SECS" ]; then
      echo "Removing stale lock $LOCK_ID [$LOCK_KEY] of age $lock_age_secs seconds placed at $LOCK_TIME for $LOCK_OP by $LOCK_HOLDER"
      [ "$DRY_RUN" ] || aws dynamodb delete-item --table-name "$LOCK_TABLE_NAME" --key "LockID={S=$LOCK_KEY}"
    else
      echo "Skipping young lock $LOCK_ID [$LOCK_KEY] of age $lock_age_secs seconds placed at $LOCK_TIME for $LOCK_OP by $LOCK_HOLDER"
    fi

  else
    echo "Skipping lock $LOCK_ID [$LOCK_KEY] of age $lock_age_secs seconds placed at $LOCK_TIME for $LOCK_OP by $LOCK_HOLDER as it was not places by $BAD_LOCKS_OWNER"
  fi

done

[ "$locks_found" ] || echo "No Terraform locks found in $LOCK_TABLE_NAME"