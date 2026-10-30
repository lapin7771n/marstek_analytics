#!/usr/bin/env python3
"""Answers ES.GetStatus on localhost so the simulator shows demo data. Usage: fake_battery.py <soc> <load_w>"""
import json
import socket
import sys

soc, load = int(sys.argv[1]), float(sys.argv[2])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", 30000))
while True:
    data, peer = sock.recvfrom(2048)
    request = json.loads(data)
    result = {"bat_soc": soc, "ongrid_power": 0, "offgrid_power": load, "bat_cap": 5120}
    sock.sendto(json.dumps({"id": request["id"], "result": result}).encode(), peer)
