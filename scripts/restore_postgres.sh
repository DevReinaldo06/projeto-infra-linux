#!/bin/bash
set -euo pipefail
umask 077

if [[ $# -ne 1 || $1 != *.tar.gz ]]; then
    echo "Uso: $0 /caminho/appdb-<data>.tar.gz" >&2
    exit 1
fi

arquivo=$1
nome=${arquivo##*/}
membro=${nome%.tar.gz}.sql
banco="appdb_restore_$(date +%Y%m%d_%H%M%S)_$$"

sql=$(mktemp)
trap 'rm -f -- "$sql"' EXIT

tar -xOzf "$arquivo" -- "$membro" > "$sql"
test -s "$sql"

createdb -- "$banco"
psql -X -v ON_ERROR_STOP=1 -1 -d "$banco" -f "$sql"
psql -X -d "$banco" -c 'SELECT count(*) AS registros_restaurados FROM public.registros;'
echo "Restauracao validada no banco $banco"
