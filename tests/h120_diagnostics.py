#!/usr/bin/env python3
"""Real notifyd processes + production POSIX opener; never touches a device daemon."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    test = str(Path(tmp)/'diagnostics')
    session = str(Path(tmp)/'session')
    for compiler, standard, language in (('clang','c11','c'), ('clang++','c++11','c++')):
        subprocess.run([compiler,'-x',language,'-std='+standard,'-Wall','-Wextra','-Werror','-pedantic',
            str(root/'tests/h120_diagnostic_session.c'),'-o',session], check=True)
        subprocess.run([session], check=True)
    subprocess.run(['clang','-std=c11','-fblocks','-Wall','-Wextra','-Werror',
        str(root/'tests/h120_diagnostics_native.c'),
        str(root/'hello120hz/Shared/H120RecordingDiagnostics.c'),'-o',test], check=True)
    subprocess.run([test,'paths'], check=True, timeout=15)
    subprocess.run([test,'probe','0','0','0'], check=True, timeout=15)
    # Run both same-UID and actual privileged-responder/unprivileged-client cases.
    # No stub notify implementation; failures/denied state writes fail CI visibly.
    for privileged in (False, True):
        for prefix, error, active in (('',0,1),('',13,0),('',2,0),('client-',120,1),('client-',60,0)):
            command = (['sudo','-n'] if privileged else []) + [test,prefix+'server',str(error),str(active)]
            server = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
            pid = None
            try:
                ready = server.stdout.readline().strip().split(); assert ready[0] == 'READY', ready
                pid = int(ready[1])
                subprocess.run([test,prefix+'probe',str(pid),str(error),str(active)], check=True, timeout=15)
                if prefix: subprocess.run([test,'probe','0','0','0'], check=True, timeout=15)
            finally:
                if pid:
                    subprocess.run((['sudo','-n'] if privileged else []) + ['kill','-TERM',str(pid)], check=True)
                else: server.terminate()
                server.wait(timeout=10)
    subprocess.run([test,'probe','0','0','0'], check=True, timeout=15)
print('PASS real notifyd across UID boundaries; target iOS sandbox still requires exported receipt')
