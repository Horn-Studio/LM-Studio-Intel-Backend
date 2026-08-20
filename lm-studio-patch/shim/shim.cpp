// llama-server shim: sets GGML_OPENVINO_DEVICE, redirects child logs to a file,
// then runs the real server. The file redirection prevents a pipe deadlock with
// LM Studio (unread stdout/stderr pipes fill up and block llama-server).
#include <windows.h>
#include <stdio.h>
#include <string.h>

static void write_log_header(HANDLE hLog, const char * msg) {
    if (!hLog) return;
    char line[512];
    SYSTEMTIME st;
    GetLocalTime(&st);
    snprintf(line, sizeof(line),
             "\r\n==== %04d-%02d-%02d %02d:%02d:%02d %s ====\r\n",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, msg);
    DWORD w = 0;
    WriteFile(hLog, line, (DWORD) strlen(line), &w, NULL);
}

int main(void) {
    // Do not override an explicit user setting
    char buf[64] = {0};
    if (GetEnvironmentVariableA("GGML_OPENVINO_DEVICE", buf, sizeof(buf)) == 0 || buf[0] == '\0') {
        SetEnvironmentVariableA("GGML_OPENVINO_DEVICE", "GPU.0");
    }
    char self[MAX_PATH];
    DWORD n = GetModuleFileNameA(NULL, self, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 2;
    char real[MAX_PATH];
    strcpy_s(real, MAX_PATH, self);
    char * slash = strrchr(real, '\\');
    if (!slash) return 3;
    strcpy_s(slash + 1, MAX_PATH - (slash + 1 - real), "llama-server-real.exe");
    // log file: <shim dir>\logs\llama-server.log
    char dirbuf[MAX_PATH];
    strcpy_s(dirbuf, MAX_PATH, self);
    char * dslash = strrchr(dirbuf, '\\');
    if (!dslash) return 3;
    *dslash = '\0';
    char logdir[MAX_PATH];
    snprintf(logdir, sizeof(logdir), "%s\\logs", dirbuf);
    CreateDirectoryA(logdir, NULL);
    char logpath[MAX_PATH];
    snprintf(logpath, sizeof(logpath), "%s\\llama-server.log", logdir);
    HANDLE hLog = CreateFileA(logpath, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    write_log_header(hLog, "llama-server (shim redirect)");
    // rebuild command line: quoted real path + original args (skip argv[0])
    const char * cmdline = GetCommandLineA();
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
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = hLog ? hLog : GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError  = hLog ? hLog : GetStdHandle(STD_ERROR_HANDLE);
    memset(&pi, 0, sizeof(pi));
    HANDLE job = CreateJobObjectA(NULL, NULL);
    if (job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION jeli;
        memset(&jeli, 0, sizeof(jeli));
        jeli.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, &jeli, sizeof(jeli));
    }
    if (!CreateProcessA(NULL, cmd, NULL, NULL, TRUE, 0, NULL, dirbuf, &si, &pi)) {
        write_log_header(hLog, "FAILED to launch real server");
        if (job) CloseHandle(job);
        if (hLog) CloseHandle(hLog);
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
    if (hLog) CloseHandle(hLog);
    return (int) code;
}
