#!/bin/bash
env
set -e
set -x
set -o pipefail

ilo_ip=$(cat /home/citest/hardware_info | awk '{print $1}')
mac=$(cat /home/citest/hardware_info | awk '{print $2}')

neutron subnet-create --name ext-subnet --allocation-pool start=169.16.1.115,end=169.16.1.116 --disable-dhcp --gateway 169.16.1.40 baremetal 169.16.1.0/24

openstack baremetal node create --driver redfish --driver-info redfish_address=$ilo_ip --driver-info redfish_username=Administrator --driver-info redfish_password=weg0th@ce@r --driver-info console_port=5000 --driver-info redfish_verify_ca="False" --driver-info redfish_system_id=/redfish/v1/Systems/1

NODE=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

openstack baremetal node set --driver-info deploy_kernel=http://169.16.1.54:9999/ipa-centos8-master_18_05_21.kernel --driver-info deploy_ramdisk=http://169.16.1.54:9999/ipa-centos8-master_tls_disabled.initramfs --driver-info bootloader=http://169.16.1.54:9999/ir-deploy-redfish.efiboot --instance-info image_source=http://169.16.1.54:9999/rhel_7.6-uefi.img --instance-info image_checksum=fd9b31d6b754b078166387c86e7fd8ce --instance-info capabilities='{"boot_mode": "uefi"}' --property capabilities='boot_mode:uefi' $NODE

openstack baremetal port create --node $NODE $mac

openstack baremetal node manage $NODE

openstack baremetal node provide $NODE

openstack baremetal node power off $NODE

# Run the tempest test.
cd /home/citest/tempest
export OS_TEST_TIMEOUT=3000
net_id=$(neutron net-list -F id -f value)
sed -i "s/11.11.11.11.11/$net_id/g" /home/citest/gate-test/tempest/etc/tempest.conf
sudo tox -e all -- ironic_standalone.test_basic_ops.BaremetalRedfishDirectWholediskHttpLink.test_ip_access_to_server
