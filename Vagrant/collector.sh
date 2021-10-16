#! /bin/bash
# This is a fully automated script which collects resource utilization data on logger machine for the given number of hosts.
# We can also control for how many iterations of "top" command, we want to collect the data for
# The script saves the results in a result.txt where the first column is number of hosts. second cpu(%) and third Ram(Mib)
# The format of this script is "collector.sh arg1 arg2" where arg1 is number of hosts and arg2 is desired number of iterations
# of top command

# This file relies on vagrant status command and should be placed beside Vagrantfile
# The host machines must have the keyword "host" in their name
check_deadscreens () {
    TMP=$(vagrant ssh -c "screen -ls | grep -c dead" $1 2>&1)
    TMP=$(echo "$TMP" | awk '{if($1==1) print "error"}')
    for ((i=0;i<10;i++))
    do
        if [[ $TMP = "error" ]]
        then
	    tput setaf 1;echo "re-attempting to start zeek-agent on $1"
            vagrant ssh -c "screen -wipe" $1
            vagrant ssh -c "screen -dmS zeekAgent; screen -S zeekAgent -X stuff 'cd /home/vagrant/projects/zeek-agent/build;sudo ./zeek-agent \n'" $1
            TMP=$(vagrant ssh -c "screen -ls | grep -c dead" $1 2>&1)
            TMP=$(echo "$TMP" | awk '{if($1==1) print "error"}')
        fi
    done
}
check_logs () {
    TMP2=$(vagrant ssh -c "cd /opt/zeek/logs/current;cat agent_process_events.log | grep -c $1" logger 2>&1)
    TMP2=$(echo "$TMP2" | awk '{if($1==0) print "error"}')
    for ((i=0;i<10;i++))
    do
        if [[ $TMP2 = "error" ]]
        then
	        tput setaf 1;echo "$1 Logs not found on logger re-starting zeek-agent on $1"
            vagrant ssh -c "pkill screen" $1
            vagrant ssh -c "screen -dmS zeekAgent; screen -S zeekAgent -X stuff 'cd /home/vagrant/projects/zeek-agent/build;sudo ./zeek-agent \n'" $1
            check_deadscreens $1
            TMP2=$(vagrant ssh -c "cd /opt/zeek/logs/current;cat agent_process_events.log | grep -c $1" logger 2>&1)
            TMP2=$(echo "$TMP2" | awk '{if($1==0) print "error"}')
        fi
    done
}

setup_host_machines () {
    tput setaf 1;echo "getting vagrant status"
    OUT=$(vagrant status)
    tput setaf 2;echo "$OUT" 
    UP=`echo "$OUT" | grep host | awk -v num=$1 'BEGIN {str=""} {if(NR<num+1) str=$1 FS str;} END {print str}'`
    DOWN=`echo "$OUT" | grep host | awk -v num=$1 'BEGIN {str=""} {if(NR>num) str=$1 FS str;} END {print str}'`
    tput setaf 1;echo "setting up $1 machines"
    echo $DOWN | awk 'BEGIN {RS=" ";} {print $0;}' | xargs -P5 -I {} vagrant halt {}
    echo $UP | awk 'BEGIN {RS=" ";} {print $0;}' | xargs -P5 -I {} vagrant up {}
    tput setaf 1;echo "checking zeek-agent-framework"
    #vagrant up logger
    vagrant ssh -c "cd /opt/zeek/bin; sudo ./zeekctl restart" logger

    IFS=' ' read -ra array <<< "$UP"
    for x in "${array[@]}"
    do
        tput setaf 2;echo "launching zeek agent on $x"
        #vagrant ssh -c "sudo kill $(pgrep zeek-agent)" $x
        vagrant ssh -c "pkill screen" $x
        vagrant ssh -c "screen -dmS zeekAgent; screen -S zeekAgent -X stuff 'cd /home/vagrant/projects/zeek-agent/build;sudo ./zeek-agent \n'" $x
        #vagrant ssh -c "nohup sudo zeek-agent &" $x
        #vagrant ssh -c "screen -wipe; screen -ls | grep zeekAgent | cut -d. -f1 | awk '{print $1}' | xargs sudo kill" $x
        check_deadscreens $x
        sleep 1
        check_logs $x
        generate_activity $x
    done
}

generate_activity(){
    vagrant ssh -c "screen -dmS workload; screen -S workload -X stuff 'sudo apt-get update;while true;do sudo apt -y install sysbench;sudo apt-get install -y apache2-utils;ab -n 10000 -c 100 www.example.com/products/
;sysbench cpu --threads=5 --cpu-max-prime=999999 run;sysbench memory --memory-total-size=2G run;sysbench fileio --file-test-mode=seqwr --file-total-size=50G run;sudo rm test_file*;done \n'" $1
    TMP=$(vagrant ssh -c "screen -ls | grep -c dead" $1 2>&1)
    TMP=$(echo "$TMP" | awk '{if($1==1) print "error"}')
    for ((i=0;i<10;i++))
    do
        if [[ $TMP = "error" ]]
        then
	    tput setaf 1;echo "re-attempting to start workload on $1"
            vagrant ssh -c "screen -wipe" $1
             vagrant ssh -c "screen -dmS workload; screen -S workload -X stuff 'sudo apt-get update;while true;do sudo apt -y install sysbench;sudo apt-get install -y apache2-utils;ab -n 10000 -c 100 www.example.com/products/;sysbench cpu --threads=5 --cpu-max-prime=999999 run;sysbench memory --memory-total-size=2G run;sysbench fileio --file-test-mode=seqwr --file-total-size=50G run;sudo rm test_file*;done \n'" $1
            TMP=$(vagrant ssh -c "screen -ls | grep -c dead" $1 2>&1)
            TMP=$(echo "$TMP" | awk '{if($1==1) print "error"}')
        fi
    done
}

collect_data () {
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
   #rm data.txt
}

setup_host_machines $1
collect_data $1 $2
