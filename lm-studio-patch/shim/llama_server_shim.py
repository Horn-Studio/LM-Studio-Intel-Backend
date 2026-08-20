# -*- coding: utf-8 -*-
"""
llama_server_shim.py - Python shim for LM Studio OpenVINO backend
Sets GGML_OPENVINO_DEVICE=GPU.0 and launches llama-server-real.exe.
Package with: pyinstaller --onefile --name llama-server.exe llama_server_shim.py
"""
import os
import sys
import subprocess
import ctypes
from pathlib import Path


class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", ctypes.c_longlong),
        ("PerJobUserTimeLimit", ctypes.c_longlong),
        ("LimitFlags", ctypes.c_ulong),
        ("MinimumWorkingSetSize", ctypes.c_size_t),
        ("MaximumWorkingSetSize", ctypes.c_size_t),
        ("ActiveProcessLimit", ctypes.c_ulong),
        ("Affinity", ctypes.c_size_t),
        ("PriorityClass", ctypes.c_ulong),
        ("SchedulingClass", ctypes.c_ulong),
    ]


class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
                ("IoInfo", ctypes.c_byte * 96)]  # IO_COUNTERS placeholder (unused)


JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
JobObjectExtendedLimitInformation = 9


def main():
    # 1) env var -> inherited by child
    if not os.environ.get("GGML_OPENVINO_DEVICE"):
        os.environ["GGML_OPENVINO_DEVICE"] = "GPU.0"

    # 2) locate real server: next to us, else in the current working directory
    self_path = Path(sys.executable if getattr(sys, "frozen", False) else __file__)
    candidates = [self_path.with_name("llama-server-real.exe"),
                  Path.cwd() / "llama-server-real.exe"]
    real = next((c for c in candidates if c.exists()), None)
    if real is None:
        print("shim: llama-server-real.exe not found", file=sys.stderr)
        sys.exit(4)

    # 3) spawn child with inherited stdio
    proc = subprocess.Popen(
        [str(real), *sys.argv[1:]],
        stdin=sys.stdin, stdout=sys.stdout, stderr=sys.stderr,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )

    # 4) job object: kill child if we die
    try:
        k32 = ctypes.windll.kernel32
        job = k32.CreateJobObjectW(None, None)
        if job:
            info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
            ctypes.memset(ctypes.byref(info), 0, ctypes.sizeof(info))
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            k32.SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                        ctypes.byref(info), ctypes.sizeof(info))
            k32.AssignProcessToJobObject(job, int(proc._handle))
            # keep the job handle open until this process exits
    except Exception as e:
        print(f"shim: job object skipped: {e}", file=sys.stderr)

    # 5) forward exit code
    sys.exit(proc.wait())


if __name__ == "__main__":
    main()
