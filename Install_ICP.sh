#!/bin/bash
#Before you begin:
#1- Request for root access - if root PermitRootLogin reuqired for SSH
#2- Make sure all nodes time synched
#3- List all nodes before executing the script
#4- Specify HA params if required
#5- Specify NFS params if required

################################################################################
####################   I C P    C O N F I G U R A T I O N   ####################
################################################################################
# Server list
cat <<'EOF' > masters.txt
10.45.125.217
EOF

# Server connection info
ssh_port=2222
ssh_user=ibm
ssh_pass=IBMDem0s!

# HA properties
ha_required=false
eth=eth0
cluster_ip=10.45.123.222
proxy_ip=10.45.123.223

# NFS
nfs_required=false
nfs_server=10.45.125.217

################################################################################

set -e +m

spinner()
{
  sp="/-\|"
  while jobs | grep -q "Running"; do
    printf "\b${sp:i++%${#sp}:1}"
    sleep 0.1
  done
  printf "\b \b"
}

my_print () {
  end_color="\e[0m"

  if [ "$2" == "info" ]; then
    color="36m"
    start_color="\e[$color"
    text="$1"
  elif [ "$2" == "ok" ]; then
    color="32m"
    start_color="\e[$color"
    text="ok      : [$1]\n"
  elif [ "$2" == "changed" ]; then
    color="93m"
    start_color="\e[$color"
    printf "$start_color%b$end_color" "changing: [$1] "
    spinner
    printf "\r"
    color="33m"
    start_color="\e[$color"
    text="changed : [$1]\n"
  elif [ "$2" == "error" ]; then
    color="91m"
    start_color="\e[$color"
    text="error   : [$1]\n"
  else #default color
    color="0m"
    start_color="\e[$color"
    text="$1"
  fi

  printf "$start_color%b$end_color" "$text" | tee -a $log_file
}

################################################################################

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

my_print "\nTASK [Check if current server listed] ******************************************\n"
my_ips="$(hostname -I)"
status="error"
for x in $my_ips; do
  if grep -Fxq "$x" masters.txt
  then
    status="ok"
    boot_node=$x
  fi
done
if [[ $status = "ok" ]]; then
  my_print "$boot_node" "ok"
else
  my_print "localhost" "error"
  exit 1
fi


my_print "\nTASK [Update packages] *********************************************************\n"
echo $ssh_pass | sudo -S -p '' apt-get update -y &>> $log_file &
my_print "localhost" "changed"


my_print "\nTASK [Install sshpass for ssh remote without user prompt] **********************\n"
if [[ -z $(which sshpass || true) ]]; then
  echo $ssh_pass | sudo -S -p '' apt-get install -y sshpass &>> $log_file &

  my_print "localhost" "changed"
else
  my_print "localhost" "ok"
fi


my_print "\nTASK [Permit root ssh login] ***************************************************\n"
if [[ $ssh_user = root ]]; then
  {
    echo $ssh_pass | sudo -S -p '' sed -i 's/^PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config &>> $log_file
    echo $ssh_pass | sudo -S -p '' service ssh restart &>> $log_file
  } &

  my_print "localhost" "changed"
else
  my_print "localhost" "ok"
fi


my_print "\nTASK [Create ssh identiry for boot node] ***************************************\n"
if [ ! -f ~/.ssh/id_rsa ]; then
  echo -e 'y' | ssh-keygen -b 4096 -f ~/.ssh/id_rsa -N "" &>> $log_file &

  if [[ $? -eq 0 ]]; then
    my_print "localhost" "changed"
  else
    my_print "localhost" "error"
  fi
else
  my_print "localhost" "ok"
fi


my_print "\nTASK [Publish ssh id] **********************************************************\n"
for x in $(cat masters.txt); do
  status=$(ssh -n -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -p $ssh_port $x echo ok 2>&1 || true)

  if [[ $status != "ok" ]]; then
    if [[ -z $(which sshpass || true) ]]; then
      ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub -p $ssh_port $ssh_user@$x -f &>> $log_file
    else
      sshpass -p$ssh_pass ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub -p $ssh_port $ssh_user@$x -f &>> $log_file &
    fi

    if [[ $? -eq 0 ]]; then
      my_print "$x" "changed"
    else
      my_print "$x" "error"
    fi
  else
    my_print "$x" "ok"
  fi
done


my_print "\nTASK [Configure bash as default shell] *****************************************\n"
for x in $(cat masters.txt); do
  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' usermod -s /bin/bash $(whoami)" &>> $log_file &

  if [[ $? -eq 0 ]]; then
    my_print "$x" "changed"
  else
    my_print "$x" "error"
  fi
done


# Check mtu > 1450
#for x in $(cat masters.txt); do ssh $x ifconfig | grep -i mtu;  done


my_print "\nTASK [Disable firewall] ********************************************************\n"
for x in $(cat masters.txt); do
  status=$(ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' ufw status" | cut -d ' ' -f2)

  if [[ $status != "inactive" ]]; then
    ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' ufw disable" &>> $log_file &

    if [[ $? -eq 0 ]]; then
      my_print "$x" "changed"
    else
      my_print "$x" "error"
    fi
  else
    my_print "$x" "ok"
  fi
done


my_print "\nTASK [Update packages] *********************************************************\n"
for x in $(cat masters.txt); do
  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' apt-get update -y" &>> $log_file &

  if [[ $? -eq 0 ]]; then
    my_print "$x" "changed"
  else
    my_print "$x" "error"
  fi
done


my_print "\nTASK [Update max map count] ****************************************************\n"
for x in $(cat masters.txt); do
  tmp=$(ssh $ssh_user@$x -p $ssh_port "sysctl vm.max_map_count | cut -d \"=\" -f2") &>> $log_file

  if [ $tmp -lt 262144 ]; then
    {
      #echo $ssh_pass | ssh $ssh_user@$x -p $ssh_port "sudo -S -p '' sh -c 'echo \"vm.max_map_count=262144\" >> /etc/sysctl.conf'"
      #ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S sed -i '/^vm.max_map_count=/{h;s/=.*/=262144/};${x;/^$/{s//vm.max_map_count=262144/;H};x}' /etc/sysctl.conf"
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i \"/^vm.max_map_count/d\" /etc/sysctl.conf" &>> $log_file
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sh -c 'echo \"vm.max_map_count=262144\" >> /etc/sysctl.conf'" &>> $log_file
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sysctl -w vm.max_map_count=262144" &>> $log_file
    } &
    if [[ $? -eq 0 ]]; then
      my_print "$x" "changed"
    else
      my_print "$x" "error"
    fi
  else
    my_print "$x" "ok"
  fi
done


my_print "\nTASK [Update hostname] *********************************************************\n"
for x in $(cat masters.txt); do
  index=1
  host_name=icp$index

  if [[ $host_name != $(hostname) ]]; then
    #ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' hostnamectl set-hostname $host_name" &>> $log_file &
    if [[ $? -eq 0 ]]; then
      my_print "$x" "changed"
    else
      my_print "$x" "error"
    fi
  else
    my_print "$x" "ok"
  fi
done


my_print "\nTASK [Update /etc/hosts] *******************************************************\n"
for x in $(cat masters.txt); do
  {
    index=1

    # Comment loopback
    ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i -e '/127.0.1.1/ s/^#*/#/' /etc/hosts" &>> $log_file

    for y in $(cat masters.txt); do
      host_name=icp$index

      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i \"/$host_name/d\" /etc/hosts" &>> $log_file
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sh -c 'echo \"$y\t$host_name\" >> /etc/hosts'" &>> $log_file

      index=$(expr $index + 1)
    done
  } &

  my_print "$x" "changed"
done


my_print "\nTASK [Install Python] *********************************************************\n"
for x in $(cat masters.txt); do
  tmp=$(ssh $ssh_user@$x -p $ssh_port "which python" || true)

  if [[ -z $tmp ]]; then
    ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' apt-get install -y python" &>> $log_file &

    if [[ $? -eq 0 ]]; then
      my_print "$x" "changed"
    else
      my_print "$x" "error"
    fi
  else
    my_print "$x" "ok"
  fi
done


my_print "\nTASK [Install pip] *************************************************************\n"
for x in $(cat masters.txt); do
  tmp=$(ssh $ssh_user@$x -p $ssh_port "which pip" || true)

  if [[ -z $tmp ]]; then
    ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' apt-get install -y python-pip" &>> $log_file &

    if [[ $? -eq 0 ]]; then
      my_print "$x" "changed"
    else
      my_print "$x" "error"
    fi
  else
    my_print "$x" "ok"
  fi
done


my_print "\nTASK [Install docker-ce] *******************************************************\n"
for x in $(cat masters.txt); do
  tmp=$(ssh $ssh_user@$x -p $ssh_port "which docker" || true)

  if [[ -z $tmp ]]; then
    {
      # Remove old packages
      #ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' apt-get remove -y docker docker-engine docker.io 2>&1 >/dev/null || true" &>> $log_file

      # Prepare docker-ce installation
      ssh $ssh_user@$x -p $ssh_port "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | { echo $ssh_pass; cat -; } | sudo -S -p '' apt-key add -" &>> $log_file
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"" &>> $log_file
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' apt-get update -y" &>> $log_file

      # Install docker-ce
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' apt-get install -y docker-ce" &>> $log_file
    } &
    if [[ $? -eq 0 ]]; then
      my_print "$x" "changed"
    else
      my_print "$x" "error"
    fi
  else
    my_print "$x" "ok"
  fi

  # Allow executing docker without sudo
  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' groupadd docker || true" &>> $log_file
  ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' usermod -aG docker ${USER}" &>> $log_file
done


if [[ $nfs_required = true ]]; then
  my_print "\nTASK [Install nfs server] ******************************************************\n"

  eval home_dir=~
  nfs_home=$home_dir/nfs

  tmp=$(ssh $ssh_user@$nfs_server -p $ssh_port "which nfsstat" || true)

  if [[ -z $tmp ]]; then
    ssh $ssh_user@$nfs_server -p $ssh_port "echo $ssh_pass | sudo -S -p '' apt-get install -y nfs-kernel-server" &>> $log_file &

    if [[ $? -eq 0 ]]; then
      my_print "$nfs_server" "changed"
    else
      my_print "$nfs_server" "error"
    fi
  else
    my_print "$nfs_server" "ok"
  fi


  my_print "\nTASK [Configure nfs server] ****************************************************\n"
  {
    IFS=. read ip_a ip_b ip_c ip_d <<< "$nfs_server"
    nfs_client_range=$ip_a.$ip_b.0.0/255.255.0.0

    # Create nfs folders
    ssh $ssh_user@$nfs_server -p $ssh_port "mkdir -p $nfs_home/registry"
    ssh $ssh_user@$nfs_server -p $ssh_port "mkdir -p $nfs_home/icp/audit"

    # Update nfs exports
    ssh $ssh_user@$nfs_server -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i \"\,$nfs_home,d\" /etc/exports"
    ssh $ssh_user@$nfs_server -p $ssh_port "echo $ssh_pass | sudo -S -p '' sh -c 'echo \"$nfs_home $nfs_client_range(rw,sync,no_subtree_check,no_root_squash)\" >> /etc/exports'"
    #ssh $ssh_user@$nfs_server -p $ssh_port "echo $ssh_pass | sudo -S -p '' sh -c 'echo \"$nfs_home *(rw,sync,no_subtree_check,no_root_squash)\" >> /etc/exports'"
    ssh $ssh_user@$nfs_server -p $ssh_port "echo $ssh_pass | sudo -S -p '' exportfs -av" &>> $log_file
  } &
  if [[ $? -eq 0 ]]; then
    my_print "$nfs_server" "changed"
  else
    my_print "$nfs_server" "error"
  fi


  my_print "\nTASK [Install nfs client] ******************************************************\n"
  for x in $(cat masters.txt); do
    tmp=$(ssh $ssh_user@$x -p $ssh_port "which nfsstat" || true)

    if [[ -z $tmp ]]; then
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' apt-get install -y nfs-common" &>> $log_file &

      if [[ $? -eq 0 ]]; then
        my_print "$x" "changed"
      else
        my_print "$x" "error"
      fi
    else
      my_print "$x" "ok"
    fi
  done


  my_print "\nTASK [Mount nfs clients] *******************************************************\n"
  for x in $(cat masters.txt); do
    {
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' mkdir -p /var/lib/registry"
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' mkdir -p /var/lib/icp/audit"

      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i \"\,/var/lib/registry,d\" /etc/fstab"
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sed -i \"\,/var/lib/icp/audit,d\" /etc/fstab"
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sh -c 'echo \"$nfs_server:$nfs_home/registry /var/lib/registry nfs rsize=8192,wsize=8192,timeo=14,intr\" >> /etc/fstab'"
      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' sh -c 'echo \"$nfs_server:$nfs_home/icp/audit /var/lib/icp/audit nfs rsize=8192,wsize=8192,timeo=14,intr\" >> /etc/fstab'"

      ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' mount -av" &>> $log_file
    } &
    if [[ $? -eq 0 ]]; then
      my_print "$x" "changed"
    else
      my_print "$x" "error"
    fi
  done
fi


my_print "\nTASK [Download installtion file] ***********************************************\n"
filename=ibm-cloud-private-x86_64-2.1.0.1.tar.gz

if [[ ! -f $filename ]]; then
  getcode="$(awk '/_warning_/ {print $NF}' /tmp/gcokie)"
  curl -Lb /tmp/gcokie "${ggURL}&confirm=${getcode}&id=${ggID}" -o "${filename}"

  if [[ $? -eq 0 ]]; then
    my_print "localhost" "changed"
  else
    my_print "localhost" "error"
  fi

  rm /tmp/gcokie
else
  my_print "localhost" "ok"
fi


my_print "\nTASK [Copy installation file] **************************************************\n"
bg_list=""
for x in $(cat masters.txt); do
  if ssh $ssh_user@$x -p $ssh_port -q "test -e $filename"; then
    my_print "$x" "ok"
  else
    scp -P $ssh_port $filename $ssh_user@$x:~ &>> $log_file &

    if [[ $? -eq 0 ]]; then
      if [[ -z $bg_list ]]; then
        bg_list="$x"
      else
        bg_list="$bg_list,$x"
      fi
    else
      my_print "$x" "error"
    fi
  fi
done
if [[ -n $bg_list ]]; then
  my_print "$bg_list" "changed"
fi



my_print "\nTASK [Load installtion file] ***************************************************\n"
bg_list=""
for x in $(cat masters.txt); do
  status=$(ssh $ssh_user@$x -p $ssh_port "echo $ssh_pass | sudo -S -p '' docker images" | wc -l)

  if [ $status -lt 78 ]; then
    ssh $ssh_user@$x -p $ssh_port "tar xf $filename -O | { echo $ssh_pass; cat -; } | sudo -S -p '' docker load" &>> $log_file &

    if [[ $? -eq 0 ]]; then
      if [[ -z $bg_list ]]; then
        bg_list="$x"
      else
        bg_list="$bg_list,$x"
      fi
    else
      my_print "$x" "error"
    fi
  else
    my_print "$x" "ok"
  fi
done
if [[ -n $bg_list ]]; then
  my_print "$bg_list" "changed"
fi


my_print "\nTASK [Extract default configuration] *******************************************\n"
echo $ssh_pass | sudo -S -p '' docker run -e LICENSE=accept -v "$(pwd)":/data ibmcom/icp-inception:2.1.0.1-ee cp -r cluster /data >/dev/null &>> $log_file
if [[ $? -eq 0 ]]; then
  my_print "localhost" "changed"
else
  my_print "localhost" "error"
fi
echo $ssh_pass | sudo -S -p '' chown -R $ssh_user:$ssh_user cluster &>> $log_file


my_print "\nTASK [Prepare icp hosts config] ************************************************\n"
echo "[master]" > ./cluster/hosts
for x in $(cat masters.txt); do
cat >> ./cluster/hosts <<EOF
$x:$ssh_port
EOF
done

echo -e "\n[worker]" >> ./cluster/hosts
for x in $(cat masters.txt); do
cat >> ./cluster/hosts <<EOF
$x:$ssh_port
EOF
done

echo -e "\n[proxy]" >> ./cluster/hosts
for x in $(cat masters.txt); do
cat >> ./cluster/hosts <<EOF
$x:$ssh_port
EOF
done

echo -e "\n[management]" >> ./cluster/hosts
for x in $(cat masters.txt); do
cat >> ./cluster/hosts <<EOF
$x:$ssh_port
EOF
done
my_print "localhost" "changed"


my_print "\nTASK [Prepare icp deployment config] *******************************************\n"
if [[ $ssh_user != root ]]; then
  #sed -i 's/.* ansible_user: .*/ansible_user: $ssh_user/' ./cluster/config.yaml
  sed -i "s/# ansible_user: <username>/ansible_user: $ssh_user/" ./cluster/config.yaml
  sed -i "s/# ansible_become: true/ansible_become: true/" ./cluster/config.yaml
  sed -i "s/# ansible_become_password: <password>/ansible_become_password: $ssh_pass/" ./cluster/config.yaml
fi

sed -i "s/# loopback_dns: false/loopback_dns: true/" ./cluster/config.yaml

if [[ $ha_required = true ]]; then
  sed -i "s/# calico_ip_autodetection_method: first-found>/calico_ip_autodetection_method: interface=$eth/" ./cluster/config.yaml
  sed -i "s/# cluster_access_ip: 0.0.0.0/cluster_access_ip: $cluster_ip/" ./cluster/config.yaml
  sed -i "s/# vip_iface: eth0/vip_iface: $eth/" ./cluster/config.yaml
  sed -i "s/# cluster_vip: 127.0.1.1/cluster_vip: $cluster_ip/" ./cluster/config.yaml
  sed -i "s/# proxy_access_ip: 0.0.0.0/proxy_access_ip: $proxy_ip/" ./cluster/config.yaml
  sed -i "s/# proxy_vip_iface: eth0/proxy_vip_iface: $eth/" ./cluster/config.yaml
  sed -i "s/# proxy_vip: 127.0.1.1/proxy_vip: $proxy_ip/" ./cluster/config.yaml
fi
cat >> ./cluster/config.yaml <<EOF

# Logging service configuration
# https://master_ip:8443/kibana
logging:
 maxAge: 1
 storage:
   es:
     size: 20Gi
     path: /opt/ibm/cfc/logging/elasticsearch
   ls:
     size: 5Gi
     path: /opt/ibm/cfc/logging/logstash
 kibana:
   install: true
EOF
my_print "localhost" "changed"


my_print "\nTASK [Final steps before deployment] *******************************************\n"
{
  echo $ssh_pass | sudo -S -p '' rm -rf cluster/cfc* cluster/misc
  echo $ssh_pass | sudo -S -p '' cp ~/.ssh/id_rsa cluster/ssh_key
  if [[ ! -f cluster/images/$filename ]]; then
    mkdir -p cluster/images
    cp $filename cluster/images/
  fi
} &
my_print "localhost" "changed"


my_print "\nTASK [Start ICP deployment] ****************************************************\n"
echo $ssh_pass | sudo -S -p '' docker run --net=host -t -e LICENSE=accept -v $(pwd)/cluster:/installer/cluster ibmcom/icp-inception:2.1.0.1-ee install | tee -a $log_file


# nothing >/dev/null 2>&1
# errors 2>&1 >/dev/null
# ???? &> /dev/null
