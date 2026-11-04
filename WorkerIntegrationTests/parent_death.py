#!/usr/bin/env python3
import os, signal, subprocess, sys, time
worker = sys.argv[1]
parent_code = r'''
import json, subprocess, sys, time
p=subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
p.stdin.write((json.dumps({'id':1,'op':'init','source':'on run\nrepeat\nend repeat\nend run'})+'\n').encode()); p.stdin.flush()
time.sleep(0.4)
p.stdin.write((json.dumps({'id':2,'op':'run'})+'\n').encode()); p.stdin.flush()
print(p.pid,flush=True)
time.sleep(60)
'''
parent = subprocess.Popen([sys.executable, '-c', parent_code, worker], stdout=subprocess.PIPE, text=True)
child = None
try:
    child = int(parent.stdout.readline())
    time.sleep(0.5)
    parent.kill(); parent.wait(timeout=3)
    deadline=time.monotonic()+7
    while time.monotonic()<deadline:
        try: os.kill(child, 0)
        except ProcessLookupError: print('PASS: busy worker exits after parent force quit'); break
        time.sleep(0.1)
    else: raise SystemExit('FAIL: worker remained after parent exited')
finally:
    if parent.poll() is None: parent.kill()
    if child is not None:
        try: os.kill(child,signal.SIGKILL)
        except ProcessLookupError: pass
