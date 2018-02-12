#!/bin/bash

################################################################################
##########################    I C P      C L E A N    ##########################
################################################################################
# Server connection info
ssh_port=2222
ssh_user=ibm
ssh_pass=IBMDem0s!

################################################################################

set -e +m

script=$(readlink -f "$0")
path=$(dirname $script)
base_file=${script%.*}
log_file=$base_file.log
start_time=$(date +"%Y%m%d_%H%M%S")
if [[ -f "$log_file" ]]; then
    cp "$log_file" "$base_file"_"$start_time"".log"
    echo "" > $log_file
else
  touch $log_file
fi

################################################################################

docker run --net=host -t -e LICENSE=accept -v $(pwd)/cluster:/installer/cluster ibmcom/icp-inception:2.1.0.1-ee uninstall | tee -a $log_file

echo $ssh_pass | sudo -S -p '' rm -rf cluster/cfc* cluster/misc | tee -a $log_file

for x in $(cat masters.txt); do
  ssh $ssh_user@$x -p $ssh_port "docker ps -a -q | xargs docker stop" | tee -a $log_file
  ssh $ssh_user@$x -p $ssh_port "docker ps -a -q | xargs docker rm" | tee -a $log_file
  ssh $ssh_user@$x -p $ssh_port "docker volume ls -q | xargs docker volume rm" | tee -a $log_file
  #ssh $ssh_user@$x -p $ssh_port "docker images -q | xargs docker rmi" | tee -a $log_file

  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i \"\,/var/lib/registry,d\" /etc/fstab"
  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i \"\,/var/lib/icp/audit,d\" /etc/fstab"
  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' mount -av" &>> $log_file

  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i -e '/127.0.1.1/ s/^#//' /etc/hosts" &>> $log_file

  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' rm -rf /opt/ibm/cfc /etc/cfc" | tee -a $log_file
  # /var/lib/kubelet
done
