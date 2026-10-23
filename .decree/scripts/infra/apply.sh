#!/usr/bin/env bash
# infra's apply: install what lib/infra/requirements declares and is missing.
exec "${DECREE_LIB}/infra/run.sh" apply
