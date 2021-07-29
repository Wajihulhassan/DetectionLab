#! /bin/bash
TMP=$(vagrant ssh -c "echo 'cat'| grep -c dead" host1 2>&1)
TMP2=$(echo "$TMP" | awk '{if($1==0) print $1}')
echo "$TMP2"
if [[ $TMP2 -eq "0" ]]
then
   echo "ok"
fi
