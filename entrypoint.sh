#!/usr/bin/env bash

event_file=event.json
diff_cmd="git diff FECH_HEAD"

if [ -f "$event_file" ]; then
  pr_branch=$(python3 -c "import sys, json; print(json.load(sys.stdin)['pull_request']['head']['ref'])" < event.json)
  base_branch=$(python3 -c "import sys, json; print(json.load(sys.stdin)['pull_request']['base']['ref'])" < event.json)
  clone_url=$(python3 -c "import sys, json; print(json.load(sys.stdin)['pull_request']['head']['repo']['clone_url'])" < event.json)
  echo "remotes:"
  git remote -v
  echo "adding new remote: $clone_url"
  git remote add pr_repo "$clone_url"
  echo "remotes:"
  git remote -v
  echo "fetching:"
  git fetch pr_repo "$pr_branch"
  git checkout "$pr_branch"
  echo "current HEAD is: "
  git rev-parse HEAD
  echo "the PR branch is $pr_branch"
  echo "the base branch is $base_branch"
  diff_cmd="git diff $base_branch $pr_branch"
  export OVERRIDE_GITHUB_EVENT_PATH=$(pwd)/event.json
fi

touch "$INPUT_LOG_FILE"
export REVIEWDOG_GITHUB_API_TOKEN="$INPUT_GITHUB_TOKEN"
rdf_log=$(mktemp)
if [ "$INPUT_SUGGEST_FIXES" = "true" ]; then
  echo "suggesting fixes"
  patch=$(mktemp)
  /opt/antmicro/action.py \
    --conf-file "$INPUT_CONFIG_FILE" \
    --extra-opts "$INPUT_EXTRA_ARGS" \
    --exclude-paths "$INPUT_EXCLUDE_PATHS" \
    --log-file "$INPUT_LOG_FILE" \
    --patch "$patch" \
    "$INPUT_PATHS"

  /opt/antmicro/rdf_gen.py \
    --efm-file "$INPUT_LOG_FILE" \
    --diff-file "$patch" > "$rdf_log"
  rm "$patch"
else
  echo "not suggesting fixes"
  /opt/antmicro/action.py \
    --conf-file "$INPUT_CONFIG_FILE" \
    --extra-opts "$INPUT_EXTRA_ARGS" \
    --exclude-paths "$INPUT_EXCLUDE_PATHS" \
    --log-file "$INPUT_LOG_FILE" \
    "$INPUT_PATHS"

  /opt/antmicro/rdf_gen.py \
    --efm-file "$INPUT_LOG_FILE" > "$rdf_log"
fi

echo "Running reviewdog"

git config --global --add safe.directory $GITHUB_WORKSPACE

"$GOBIN"/reviewdog -f=rdjson \
  -reporter="$INPUT_REVIEWDOG_REPORTER" \
  -fail-on-error="$INPUT_FAIL_ON_ERROR" \
  -name="verible-verilog-lint" \
  -diff="$diff_cmd" < "$rdf_log" || exitcode=$?

if [ -f "$event_file" ]; then
  git checkout -
fi

exit $exitcode
