#!/bin/bash
env
set -x
set -e

handle_exception() {
  c_out=$?
  if [ $c_out -ne 0 ]; then
    echo "Gate job failed. Releasing node..."
    /home/citest/NEW-HPE-CI-JOBS/molteniron/release_molten.py $uuid
  fi
}

trap "handle_exception" EXIT

echo "***********Running ilo-ipxe gate**********"

echo "Setting gate environment."
uuid=$2
myip=$(ip -f inet addr show eth0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
ilo_ip=$(cat /home/citest/hardware_info | awk '{print $1}')
mac=$(cat /home/citest/hardware_info | awk '{print $2}')
pool=$(cat /home/citest/hardware_info | awk '{print $3}')
str=$(echo $pool|cut -d "," -f 1)
end=$(echo $pool|cut -d "," -f 2)
patch_id=$1

echo "Injecting ironic patch."
docker cp /home/citest/NEW-HPE-CI-JOBS/ironic-patch-injection ironic_conductor:/citest
docker cp /home/citest/NEW-HPE-CI-JOBS/ironic-patch-injection ironic_api:/citest
docker exec -u root ironic_conductor bash /citest/ironic-patch-injection $patch_id
docker exec -u root ironic_api bash /citest/ironic-patch-injection $patch_id

echo "Making other ironic changes."
sudo sed -i 's/dhcp_provider = none/dhcp_provider = dnsmasq/g' /etc/kolla/ironic-conductor/ironic.conf
sudo sed -i '/^\[ilo\]$/,/^\[/ s/^use_web_server_for_images = true/use_web_server_for_images = true\nkernel_append_params = \"ipa-insecure=True\"/' /etc/kolla/ironic-conductor/ironic.conf
docker restart ironic_api
docker restart ironic_conductor
sleep 10

echo "Create neutron network."
openstack network create  --provider-network-type flat --provider-physical-network provider --share baremetal
openstack subnet create --allocation-pool start=$str,end=$end --no-dhcp --gateway 169.16.1.40 --network baremetal ext-subnet --subnet-range 169.16.1.0/24

echo "Configuring external dhcp."
docker stop ironic_dnsmasq
cat <<EOF >/tmp/dhcpd.conf
allow booting;
default-lease-time 600;
max-lease-time 7200;

subnet 169.16.1.0 netmask 255.255.255.0 {
        deny unknown-clients;
}

host ilo {
                hardware ethernet $mac;
                fixed-address $end;
                filename "ipxe.efi";
                next-server $myip;
                if exists user-class and option user-class = "iPXE" {
                        filename "http://$myip:8089/boot.ipxe";
                } else {
                        filename "ipxe.efi";
                }
}
EOF
sudo cp /tmp/dhcpd.conf /etc/dhcp/dhcpd.conf
sudo systemctl restart dhcpd.service

echo "Creating ironic node."
openstack baremetal node create --driver ilo --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info ilo_verify_ca=False --boot-interface ilo-ipxe --deploy-interface direct
NODE=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)
openstack baremetal node set --driver-info deploy_kernel=http://169.16.1.40:9000/kesper-ipa.kernel --driver-info deploy_ramdisk=http://169.16.1.40:9000/kesper-ipa.initramfs --driver-info bootloader=http://169.16.1.40:9000/ir-deploy-redfish.efiboot --instance-info image_source=http://169.16.1.40:9000/rhel009_wholedisk_image.qcow2 --instance-info image_checksum=6d2a8427a4608d1fcc7aa2daed8ad5c6 --instance-info root_gb=25  --property capabilities='boot_mode:uefi' --property cpus=1 --property memory_mb=24288 --property local_gb=40 --property cpu_arch=x86_64 $NODE
openstack baremetal port create --node $NODE $mac
openstack baremetal node manage $NODE
sleep 10
openstack baremetal node provide $NODE
openstack baremetal node power off $NODE

echo "Executing gate test."
cd /home/citest/gate-test/tempest
export OS_TEST_TIMEOUT=3000
net_id=$(openstack network list -f value -c ID)
sed -i "s/11.11.11.11.11/$net_id/g" /home/citest/gate-test/tempest/etc/tempest.conf
sudo -E stestr -vvv --debug run --serial ironic_standalone.test_basic_ops.BaremetalIloIPxeWholediskHttpLink.test_ip_access_to_server
openstack baremetal node list|grep "active"

echo "Releasing node..."
/home/citest/NEW-HPE-CI-JOBS/molteniron/release_molten.py $uuid
echo "***********ilo-ipxe gate: PASSED**********"