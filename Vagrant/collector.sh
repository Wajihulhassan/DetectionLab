#! /bin/bash
# the host machines must have the keyword "host" in their name
# the format of this script is collector.sh arg1 arg2 where arg1 is number of hosts and arg2 is number of iterations
tput setaf 1;echo "getting vagrant status"
OUT=$(vagrant status)
tput setaf 2;echo "$OUT" 
UP=`echo "$OUT" | grep host | awk -v num=$1 'BEGIN {str=""} {if(NR<num+1) str=$1 FS str;} END {print str}'`
DOWN=`echo "$OUT" | grep host | awk -v num=$1 'BEGIN {str=""} {if(NR>num) str=$1 FS str;} END {print str}'`
tput setaf 1;echo "setting up $1 machines"
echo $UP | awk 'BEGIN {RS=" ";} {print $0;}' | xargs -P5 -I {} vagrant up {}
#echo $DOWN | awk 'BEGIN {RS=" ";} {print $0;}' | xargs -P5 -I {} vagrant halt {}
tput setaf 1;echo "checking zeek-agent-framework"
#vagrant up logger
#vagrant ssh -c "cd /opt/zeek/bin; sudo ./zeekctl restart" logger
IFS=' ' read -ra array <<< "$UP"
for x in "${array[@]}"
do
    tput setaf 2;echo "launching zeek agent on $x"
    vagrant ssh -c "sudo kill $(pgrep zeek-agent)" $x
    vagrant ssh -c "nohup sudo zeek-agent </dev/null &>/dev/null &" $x
    #vagrant ssh -c "screen -wipe; screen -ls | grep zeekAgent | cut -d. -f1 | awk '{print $1}' | xargs kill" $x
    #vagrant ssh -c "screen -d -m -S zeekAgent; screen -S zeekAgent -X stuff 'sudo zeek-agent \n'" $x
done
sleep 10
touch data.txt
vagrant upload $PWD"/data.txt" logger
tput setaf 2;echo "collecting data for $2 iterations of top"
vagrant ssh -c "top n $2 > data.txt" logger
vagrant ssh -c "cat data.txt" logger > data.txt
vagrant ssh -c "rm data.txt" logger
CPU=`grep zeek data.txt | awk '{ sum += $10; n++ } END { if (n > 0) print sum / n; }'`
RAM=`grep zeek data.txt | awk '{ sum += $11; n++ } END { if (n > 0) print (sum*7819.7)/(100*n); }'`
echo "$1 $CPU $RAM" >> result.txt
tput setaf 1;echo "The data is collected in result.txt"
rm data.txt
