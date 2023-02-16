#!/usr/bin/python3
import subprocess
import json
import sys

print("Molteniron release node...")
owner_name = sys.argv[1]
try:
    out = subprocess.check_output(['bash', '-c', "molteniron release '%s'" % owner_name])
    out_d = json.loads(out)
    if int(out_d['status']) == 200:
        print("Node released Successfully")
except:
    print("No node to release.")
