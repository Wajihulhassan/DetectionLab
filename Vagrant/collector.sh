#! /bin/bash

UP=`vagrant status | grep host | awk -v num=$1 'BEGIN {str=""} {if(NR<num+1) str=$1 FS str;} END {print str}'`
DOWN=`vagrant status | grep host | awk -v num=$1 'BEGIN {str=""} {if(NR>num) str=$1 FS str;} END {print str}'`
vagrant up $UP
vagrant halt $DOWN
IFS=' ' read -ra array <<< "$UP"
for x in "${array[@]}"
do
    vagrant ssh -c "screen -ls | grep Detached | cut -d. -f1 | awk '{print $1}' | xargs kill" $x
    vagrant ssh -c "screen -d -m -S zeekAgent; screen -S zeekAgent -X stuff 'sudo zeek-agent \n'" $x
done
vagrant up logger
vagrant ssh -c "top n 20 > data.txt" logger
vagrant ssh -c 
