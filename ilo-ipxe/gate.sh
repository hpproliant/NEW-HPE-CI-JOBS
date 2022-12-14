#!/bin/bash
env
set -e
set -x
set -o pipefail

echo "***********Running ilo-ipxe gate**********"

myip=$(ip -f inet addr show eth0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
ilo_ip=$(cat /home/citest/hardware_info | awk '{print $1}')
mac=$(cat /home/citest/hardware_info | awk '{print $2}')
pool=$(cat /home/citest/hardware_info | awk '{print $3}')
str=$(echo $pool|cut -d "," -f 1)
end=$(echo $pool|cut -d "," -f 2)
sudo sed -i 's/dhcp_provider = none/dhcp_provider = dnsmasq/g' /etc/kolla/ironic-conductor/ironic.conf
docker restart ironic_conductor
docker stop ironic_dnsmasq

echo "Configure external DHCP."
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

neutron subnet-create --name ext-subnet --allocation-pool start=$str,end=$end --disable-dhcp --gateway 169.16.1.40 baremetal 169.16.1.0/24

sleep 5

openstack baremetal node create --driver ilo --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info ilo_verify_ca=False --boot-interface ilo-ipxe --deploy-interface direct

NODE=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

openstack baremetal node set --driver-info deploy_kernel=http://169.16.1.40:9000/kesper-ipa.kernel --driver-info deploy_ramdisk=http://169.16.1.40:9000/kesper-ipa.initramfs --driver-info bootloader=http://169.16.1.40:9000/ir-deploy-redfish.efiboot --instance-info image_source=http://169.16.1.40:9000/rhel009_wholedisk_image.qcow2 --instance-info image_checksum=6d2a8427a4608d1fcc7aa2daed8ad5c6 --instance-info root_gb=25  --property capabilities='boot_mode:uefi' $NODE

openstack baremetal port create --node $NODE $mac

openstack baremetal node set --property cpus=1 --property memory_mb=24288 --property local_gb=40 --property cpu_arch=x86_64 $NODE

openstack baremetal node manage $NODE

sleep 10

openstack baremetal node provide $NODE

openstack baremetal node power off $NODE

# Run the tempest test.
cd /home/citest/gate-test/tempest
export OS_TEST_TIMEOUT=3000
net_id=$(neutron net-list -F id -f value)
sed -i "s/11.11.11.11.11/$net_id/g" /home/citest/gate-test/tempest/etc/tempest.conf
sudo -E stestr -v run --serial ironic_standalone.test_basic_ops.BaremetalIloIPxeWholediskHttpLink.test_ip_access_to_server

echo "***********Successfully passed ilo-ipxe gate**********"
