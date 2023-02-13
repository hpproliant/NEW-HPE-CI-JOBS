#!/bin/bash
env
set -e
set -x
set -o pipefail

echo "*********Started running 'ilo5-uefi-https' gate*************"

my_ip=$(ip -f inet addr show eth0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
ilo_ip=$(cat /home/citest/hardware_info | awk '{print $1}')
mac=$(cat /home/citest/hardware_info | awk '{print $2}')
pool=$(cat /home/citest/hardware_info | awk '{print $3}')
str=$(echo $pool|cut -d "," -f 1) 
end=$(echo $pool|cut -d "," -f 2) 

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
}
EOF
sudo cp /tmp/dhcpd.conf /etc/dhcp/dhcpd.conf
sudo systemctl restart dhcpd.service
docker stop ironic_dnsmasq

echo "Configure tls based webserver."
mkdir /home/citest/ssl_files
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /home/citest/ssl_files/uefi_signed.key -out /home/citest/ssl_files/uefi_signed.crt -subj "/C=IN/ST=K/CN=$my_ip"
docker exec -it ironic_http mkdir /root/ssl_files
docker cp /home/citest/ssl_files/uefi_signed.crt ironic_http:/root/ssl_files/
docker cp /home/citest/ssl_files/uefi_signed.key ironic_http:/root/ssl_files/
sudo rm -f /etc/kolla/ironic-http/httpd.conf
sudo cp /home/citest/NEW-HPE-CI-JOBS/ilo5-uefi-https/files/httpd.conf /etc/kolla/ironic-http/httpd.conf
sudo sed -i "s/8.8.8.8/$my_ip/g" /etc/kolla/ironic-http/httpd.conf
docker restart ironic_http

echo "Upload tls cert."
docker exec -it ironic_conductor mkdir /root/ssl_files
docker cp /home/citest/ssl_files/uefi_signed.crt ironic_conductor:/root/ssl_files/
docker cp /home/citest/ssl_files/uefi_signed.key ironic_conductor:/root/ssl_files/

echo "Ironic changes."
sudo sed -i '/^\[DEFAULT\]$/,/^\[/ s/^debug = True/webserver_verify_ca = \/root\/ssl_files\/uefi_signed.crt/' /etc/kolla/ironic-conductor/ironic.conf
sudo sed -i '/^\[ilo\]$/,/^\[/ s/^use_web_server_for_images = true/use_web_server_for_images = true\nkernel_append_params = \"ipa-insecure=True\"/' /etc/kolla/ironic-conductor/ironic.conf
sudo sed -i "/^\[deploy\]$/,/^\[/ s/^http_url = http:\/\/$my_ip:8089/http_url = https:\/\/$my_ip:443/" /etc/kolla/ironic-conductor/ironic.conf
docker restart ironic_conductor

echo "Tempest changes."
sed -i "s/http:\/\/169.16.1.40:9000\/rhel009_wholedisk_image.qcow2/https:\/\/$my_ip:443\/rhel009_wholedisk_image.qcow2/g" /home/citest/gate-test/tempest/etc/tempest.conf

neutron subnet-create --name ext-subnet --allocation-pool start=$str,end=$end --disable-dhcp --gateway 169.16.1.40 baremetal 169.16.1.0/24

sleep 5

openstack baremetal node create --driver ilo5 --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info ilo_verify_ca=False --boot-interface ilo-uefi-https --deploy-interface direct --management-interface ilo5 

NODE=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

openstack baremetal node set --driver-info deploy_kernel=https://$my_ip:443/ironic-agent.kernel --driver-info deploy_ramdisk=https://$my_ip:443/ironic-agent.initramfs --driver-info bootloader=https://$my_ip:443/ir-deploy-redfish.efiboot --instance-info image_source=https://$my_ip:443/rhel009_wholedisk_image.qcow2 --instance-info image_checksum=6d2a8427a4608d1fcc7aa2daed8ad5c6 --instance-info root_gb=25  --property capabilities='boot_mode:uefi' --property cpus=1 --property memory_mb=24288 --property local_gb=40 --property cpu_arch=x86_64 $NODE

openstack baremetal port create --node $NODE $mac

openstack baremetal node manage $NODE

sleep 10

openstack baremetal node provide $NODE

openstack baremetal node power off $NODE

# Run the tempest test.
cd /home/citest/gate-test/tempest
export OS_TEST_TIMEOUT=3000
net_id=$(neutron net-list -F id -f value)
sed -i "s/11.11.11.11.11/$net_id/g" /home/citest/gate-test/tempest/etc/tempest.conf
sudo -E stestr -vvv --debug run --serial ironic_standalone.test_basic_ops.BaremetalIlo5UefiHTTPSWholediskHttpsLink.test_ip_access_to_server
if [ $? -ne 0 ]; then
    exit 1
fi
echo "*********Completed 'ilo5-uefi-https' gate*************"
