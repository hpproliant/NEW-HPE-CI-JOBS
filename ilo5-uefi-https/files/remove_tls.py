import sys
import time
import proliantutils.ilo.client as client

from OpenSSL.crypto import load_certificate, FILETYPE_PEM

cert_file_string = open("/root/ssl_files/uefi_signed.crt", "rb").read()
cert = load_certificate(FILETYPE_PEM, cert_file_string)
fp = cert.digest("sha1").decode('ASCII')
ilo_ip = sys.argv[1]
cl=client.IloClient(ilo_ip, "Administrator", "weg0th@ce@r")
#remove certificate
cl.remove_tls_certificate([fp])