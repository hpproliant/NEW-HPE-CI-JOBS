#!/bin/bash
env
set -e
set -x
set -o pipefail

echo "*********Started running 'ilo5-uefi-https' gate*************"

ilo_ip=$(cat /home/citest/hardware_info | awk '{print $1}')
mac=$(cat /home/citest/hardware_info | awk '{print $2}')

# This part will test while testing
python3 /tmp/uefi-https/HPE-CI-JOBS/ilo5-uefi-https/files/ilo5_upload_cert.py $ilo_ip

neutron subnet-create --name ext-subnet --allocation-pool start=169.16.1.119,end=169.16.1.120 --disable-dhcp --gateway 169.16.1.40 baremetal 169.16.1.0/24

openstack baremetal node create --driver ilo5 --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info ilo_verify_ca=False --boot-interface ilo-uefi-https --deploy-interface direct --management-interface ilo5 

NODE=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

openstack baremetal node set --driver-info deploy_kernel=https://169.16.1.40:443/kesper-ipa.kernel --driver-info deploy_ramdisk=https://169.16.1.40:443/kesper-ipa.initramfs --driver-info bootloader=https://169.16.1.40:443/ir-deploy-redfish.efiboot --instance-info image_source=https://169.16.1.40:443/rhel009_wholedisk_image.qcow2 --instance-info image_checksum=6d2a8427a4608d1fcc7aa2daed8ad5c6 --instance-info root_gb=25  --property capabilities='boot_mode:uefi' $NODE

openstack baremetal port create --node $NODE $mac

openstack baremetal node set --property cpus=1 --property memory_mb=24288 --property local_gb=40 --property cpu_arch=x86_64 $NODE

openstack baremetal node manage $NODE

openstack baremetal node provide $NODE

openstack baremetal node power off $NODE

# Run the tempest test.
cd /home/citest/tempest
export OS_TEST_TIMEOUT=3000
net_id=$(neutron net-list -F id -f value)
sed -i "s/11.11.11.11.11/$net_id/g" /home/citest/gate-test/tempest/etc/tempest.conf
sudo tox -e all -- ironic_standalone.test_basic_ops.BaremetalIlo5UefiHTTPSWholediskHttpsLink.test_ip_access_to_server

echo "*********Completed 'ilo5-uefi-https' gate*************"