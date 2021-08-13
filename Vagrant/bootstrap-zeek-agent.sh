#! /bin/bash

# Override existing DNS Settings using netplan, but don't do it for Terraform builds
if ! curl -s 169.254.169.254 --connect-timeout 2 >/dev/null; then
  echo -e "    eth1:\n      dhcp4: true\n      nameservers:\n        addresses: [8.8.8.8,8.8.4.4]" >>/etc/netplan/01-netcfg.yaml
  netplan apply
fi
sed -i 's/nameserver 127.0.0.53/nameserver 8.8.8.8/g' /etc/resolv.conf && chattr +i /etc/resolv.conf

FIXED_IP=$1

export DEBIAN_FRONTEND=noninteractive
echo "apt-fast apt-fast/maxdownloads string 10" | debconf-set-selections
echo "apt-fast apt-fast/dlflag boolean true" | debconf-set-selections

sed -i "2ideb mirror://mirrors.ubuntu.com/mirrors.txt focal main restricted universe multiverse\ndeb mirror://mirrors.ubuntu.com/mirrors.txt focal-updates main restricted universe multiverse\ndeb mirror://mirrors.ubuntu.com/mirrors.txt focal-backports main restricted universe multiverse\ndeb mirror://mirrors.ubuntu.com/mirrors.txt focal-security main restricted universe multiverse" /etc/apt/sources.list

apt_install_prerequisites() {
  echo "[$(date +%H:%M:%S)]: Adding apt repositories..."
  # Add repository for apt-fast
  add-apt-repository -y ppa:apt-fast/stable
  # Add repository for yq
  add-apt-repository -y ppa:rmescandon/yq
  # Install prerequisites and useful tools
  echo "[$(date +%H:%M:%S)]: Running apt-get clean..."
  apt-get clean
  echo "[$(date +%H:%M:%S)]: Running apt-get update..."
  apt-get -qq update
  apt-get -qq install -y apt-fast
  echo "[$(date +%H:%M:%S)]: Running apt-fast install..."
  apt-fast -qq install -y jq whois git unzip yq cppcheck ccache curl flex bison rpm doxygen ninja-build graphviz clang cmake auditd ifupdown libaudit-dev pkg-config unzip uthash-dev curl audispd-plugins libunwind-dev crudini
  echo "[$(date +%H:%M:%S)]: Changing default compilers..."
  sudo update-alternatives --set cc /usr/bin/clang
  sudo update-alternatives --set c++ /usr/bin/clang++
  
  # colorful terminal
  sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' /root/.bashrc
  sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' /home/vagrant/.bashrc

}

test_prerequisites() {
  for package in jq whois git unzip yq cppcheck ccache curl flex bison rpm doxygen ninja-build graphviz clang cmake auditd ifupdown libaudit-dev pkg-config unzip uthash-dev curl audispd-plugins libunwind-dev; do
    echo "[$(date +%H:%M:%S)]: [TEST] Validating that $package is correctly installed..."
    # Loop through each package using dpkg
    if ! dpkg -S $package >/dev/null; then
      # If which returns a non-zero return code, try to re-install the package
      echo "[-] $package was not found. Attempting to reinstall."
      apt-get -qq update && apt-get install -y $package
      if ! which $package >/dev/null; then
        # If the reinstall fails, give up
        echo "[X] Unable to install $package even after a retry. Exiting."
        exit 1
      fi
    else
      echo "[+] $package was successfully installed!"
    fi
  done
}

fix_eth1_static_ip() {
  USING_KVM=$(sudo lsmod | grep kvm)
  if [ -n "$USING_KVM" ]; then
    echo "[*] Using KVM, no need to fix DHCP for eth1 iface"
    return 0
  fi
  if [ -f /sys/class/net/eth2/address ]; then
    if [ "$(cat /sys/class/net/eth2/address)" == "00:50:56:a3:b1:c4" ]; then
      echo "[*] Using ESXi, no need to change anything"
      return 0
    fi
  fi
  # There's a fun issue where dhclient keeps messing with eth1 despite the fact
  # that eth1 has a static IP set. We workaround this by setting a static DHCP lease.
  echo -e 'interface "eth1" {
    send host-name = gethostname();
    send dhcp-requested-address ${FIXED_IP};
  }' >>/etc/dhcp/dhclient.conf
  netplan apply
  # Fix eth1 if the IP isn't set correctly
  ETH1_IP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
  if [ "$ETH1_IP" != ${FIXED_IP} ]; then
    echo "Incorrect IP Address settings detected. Attempting to fix."
    ifdown eth1
    ip addr flush dev eth1
    ifup eth1
    ETH1_IP=$(ifconfig eth1 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)
    if [ "$ETH1_IP" == ${FIXED_IP} ]; then
      echo "[$(date +%H:%M:%S)]: The static IP has been fixed and set to ${FIXED_IP}"
    else
      echo "[$(date +%H:%M:%S)]: Failed to fix the broken static IP for eth1. Exiting because this will cause problems with other VMs."
      exit 1
    fi
  fi

  # Make sure we do have a DNS resolution
  while true; do
    if [ "$(dig +short @8.8.8.8 github.com)" ]; then break; fi
    sleep 1
  done
}

install_zeek_agent() {
    sudo mkdir /etc/zeek-agent/

    sudo cat << 'EOF' >> /etc/zeek-agent/config.json
{
  "server_address": "192.168.38.105",
  "server_port": 9999,

  "log_folder": "/var/log/zeek",
  "max_queued_row_count": 5000,
  "osquery_extensions_socket": "/var/osquery/osquery.em",
  "group_list": []
}
EOF

    sudo mkdir /var/log/zeek/
    sudo apt-get install -y zip

    mkdir -p /home/vagrant/projects/
    cd /home/vagrant/projects/
    # git clone https://github.com/zeek/zeek-agent.git --recursive
    git clone https://github.com/Wajihulhassan/zeek-agent --recursive
    # cd zeek-agent/
    # mkdir ./build/
    # cd  build
    # cmake -DCMAKE_BUILD_TYPE:STRING=RelWithDebInfo -DZEEK_AGENT_ENABLE_INSTALL:BOOL=ON -DZEEK_AGENT_ENABLE_TESTS:BOOL=ON -DZEEK_AGENT_ZEEK_COMPATIBILITY:STRING="3.1" /home/vagrant/projects/zeek-agent/
    # cmake --build . -j2
    # # mkdir -p zeek-agent
    # # cd zeek-agent
    # # wget https://github.com/hamzashahzad1/zeek-agent/releases/download/refs%2Fheads%2Fmaster/zeek31_zeek-agent.zip
    # # unzip zeek31_zeek-agent.zip
    # nohup ./zeek-agent &
    bg_pid=$!
    # echo "${bg_pid}" > zeek-agent.pid

    # cd /home/vagrant/
    # chown -R vagrant:vagrant ./projects
    # echo export PATH="$PATH:/home/vagrant/projects/zeek-agent/build" >>~/.bashrc
}

install_config_auditd() {

    sudo cat << 'EOF' >> /etc/audit/rules.d/10-zeek_agent.rules
-a exit,always -F arch=b64 -S execve
-a exit,always -F arch=b64 -S execveat
-a exit,always -F arch=b64 -S fork
-a exit,always -F arch=b64 -S vfork
-a exit,always -F arch=b64 -S clone
-a exit,always -F arch=b64 -S connect
-a exit,always -F arch=b64 -S bind
-a exit,always -F arch=b64 -S open
-a exit,always -F arch=b64 -S openat
EOF
    sudo systemctl enable --now auditd
    sudo sed -i 's/no/yes/g' /etc/audisp/plugins.d/af_unix.conf
    sudo cp /vagrant/resources/auditd/auditd.conf /etc/audit/
    sudo systemctl restart auditd
    sudo auditctl -e1 -b 1024
}

install_splunk_forwarder() {
    dpkg -i /vagrant/resources/splunk_forwarder/splunkforwarder-8.0.6-152fb4b2bb96-linux-2.6-amd64.deb
    /opt/splunkforwarder/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd changeme
    /opt/splunkforwarder/bin/splunk add forward-server 192.168.38.105:9997 -auth admin:changeme
    /opt/splunkforwarder/bin/splunk install app /vagrant/resources/splunk_server/splunk-add-on-for-unix-and-linux_820.tgz -auth admin:changeme
    mkdir -p /opt/splunkforwarder/etc/apps/Splunk_TA_nix/local && touch /opt/splunkforwarder/etc/apps/Splunk_TA_nix/local/inputs.conf

    crudini --set /opt/splunkforwarder/etc/apps/Splunk_TA_nix/local/inputs.conf script://./bin/ps.sh interval 5
    crudini --set /opt/splunkforwarder/etc/apps/Splunk_TA_nix/local/inputs.conf script://./bin/ps.sh sourcetype ps
    crudini --set /opt/splunkforwarder/etc/apps/Splunk_TA_nix/local/inputs.conf script://./bin/ps.sh source ps
    crudini --set /opt/splunkforwarder/etc/apps/Splunk_TA_nix/local/inputs.conf script://./bin/ps.sh index linux
    crudini --set /opt/splunkforwarder/etc/apps/Splunk_TA_nix/local/inputs.conf script://./bin/ps.sh disabled 0

    /opt/splunkforwarder/bin/splunk restart
}

main() {
  apt_install_prerequisites
  modify_motd
  test_prerequisites
  fix_eth1_static_ip
  install_config_auditd
  install_zeek_agent
  # install_splunk_forwarder
}

main
exit 0
