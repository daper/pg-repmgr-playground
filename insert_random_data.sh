#!/bin/sh

export PGHOST=
export PGUSER=

export SHELL=$(type -p bash)

doit () {
  RESP=$(psql -t -c "insert into test values ('$1')")
  if [ $? -ne 0 ]; then
    echo "$RESP" >> errors.txt
  fi
}

export -f doit

touch errors.txt
tail -f -n0 errors.txt &

PARALLEL=2
INSERTS=20
while true; do
  STRS=()
  for (( i = 1; i <= $INSERTS; i++ )); do
    random_data=$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64 -w 0 | rev | cut -b 2- | rev)
    STRS+=($random_data)
  done

  parallel -j2 doit ::: ${STRS[@]}

  records_t=$(psql -t -c "select count(*) from test" | sed -E 's/\s+//g' | tr -d $'\n')
  echo "Total records: $records_t"

  if [ $records_t -gt 10000 ]; then
    psql -t -c "delete from test"
  fi

  sleep 0.5
done