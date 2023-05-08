#!/usr/bin/python3
import subprocess
import json
import sys
import mysql.connector
from datetime import datetime

try:
    connection = mysql.connector.connect(host='127.0.0.1', database='MoltenIron', user='root', password='12iso*help')
    sql_select_Query = "select provisioned from Nodes where (UNIX_TIMESTAMP(timestamp) + 3600 < UNIX_TIMESTAMP());"
    cursor = connection.cursor()
    cursor.execute(sql_select_Query)
    records = cursor.fetchall()
    for row in records:
        out = subprocess.check_output(['bash', '-c', "molteniron release '%s'" % row[0]])
        msg = "Node released: " + row[0] + "\n"
        print(msg)
        with open('/tmp/molten-'+datetime.today().strftime('%Y-%m-%d'), 'a') as f:
            f.write(msg)
except mysql.connector.Error as e:
    print("Error reading data from MySQL table", e)
finally:
    if connection.is_connected():
        connection.close()
        cursor.close()
        print("MySQL connection is closed")