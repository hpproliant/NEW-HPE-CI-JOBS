#!/bin/bash
env
set -e
set -x
set -o pipefail

echo "Deploy Kolla ansible."
kolla-ansible -i /home/citest/all-in-one deploy

echo "Configure Neutron."
myip=$(ip -f inet addr show eth1 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
openstack user create --domain default --password 12iso*help neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://$myip:9696
openstack endpoint create --region RegionOne network internal http://$myip:9696
openstack endpoint create --region RegionOne network admin http://$myip:9696
neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head
systemctl start openvswitch.service
systemctl start neutron-server.service neutron-openvswitch-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-ovs-cleanup.service
sleep 5
openstack network create  --provider-network-type flat --provider-physical-network provider --share baremetal
neutron subnet-create --name ext-subnet --allocation-pool start=169.16.1.111,end=169.16.1.112 --disable-dhcp --gateway 169.16.1.40 baremetal 169.16.1.0/24

echo "Configure Tempest."
net_id=$(neutron net-list -F id -f value)
sed -i "s/11.11.11.11.11/$net_id/g" /home/citest/gate-test/tempest/etc/tempest.conf