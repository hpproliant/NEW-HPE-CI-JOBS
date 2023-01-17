#!/bin/bash
env
set -e
set -x
set -o pipefail

echo "Deploy Kolla ansible."
export ANSIBLE_LOG_PATH=/home/citest/gate_logs/ansible_kolla_deploy.log 
kolla-ansible -i /home/citest/all-in-one deploy
sleep 60
echo "Configure Neutron."
myip=$(ip -f inet addr show eth0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
openstack user create --domain default --password 12iso*help neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://$myip:9696
openstack endpoint create --region RegionOne network internal http://$myip:9696
openstack endpoint create --region RegionOne network admin http://$myip:9696
neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head
sudo systemctl start openvswitch.service
sudo systemctl start neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-ovs-cleanup.service
sleep 5
openstack network create  --provider-network-type flat --provider-physical-network provider --share baremetal
