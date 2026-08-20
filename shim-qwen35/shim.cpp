// llama-server shim: sets GGML_OPENVINO_DEVICE then runs the real server
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    // Do not override an explicit user setting
    char buf[64] = {0};
    if (GetEnvironmentVariableA("GGML_OPENVINO_DEVICE", buf, sizeof(buf)) == 0 || buf[0] == '\0') {
        SetEnvironmentVariableA("GGML_OPENVINO_DEVICE", "GPU.0");
    }
    char self[MAX_PATH];
    DWORD n = GetModuleFileNameA(NULL, self, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 2;
    // real server sits next to us
    char real[MAX_PATH];
    strcpy_s(real, MAX_PATH, self);
    char * slash = strrchr(real, '\\');
    if (!slash) return 3;
    strcpy_s(slash + 1, MAX_PATH - (slash + 1 - real), "llama-server-real.exe");
    // rebuild command line: quoted real path + original args (skip argv[0])
    const char * cmdline = GetCommandLineA();
    // strip the first token (quoted or not)
    const char * p = cmdline;
    while (*p == ' ') p++;
    if (*p == '"') { p++; while (*p && *p != '"') p++; if (*p == '"') p++; }
    else { while (*p && *p != ' ') p++; }
    char cmd[32768];
    snprintf(cmd, sizeof(cmd), "\"%s\"%s", real, p);
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    memset(&pi, 0, sizeof(pi));
    // job object: kill child when this process exits
    HANDLE job = CreateJobObjectA(NULL, NULL);
    if (job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION jeli;
        memset(&jeli, 0, sizeof(jeli));
        jeli.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, &jeli, sizeof(jeli));
    }
    if (!CreateProcessA(NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
        fprintf(stderr, "shim: failed to launch %s (err %lu)\n", real, GetLastError());
        if (job) CloseHandle(job);
        return 4;
    }
    if (job) {
        AssignProcessToJobObject(job, pi.hProcess);
        // keep the job handle open until this process exits; the OS closes it
        // automatically at exit, which then kills the child if still running
    }
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    return (int) code;
}
