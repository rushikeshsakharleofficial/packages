#define UNICODE
#define _UNICODE
#include <windows.h>
#include <wchar.h>
#include <stdio.h>

static SERVICE_STATUS_HANDLE g_status_handle;
static SERVICE_STATUS g_status;
static HANDLE g_child = NULL;
static HANDLE g_stop_event = NULL;
static HANDLE g_job = NULL;

static void set_status(DWORD state, DWORD win32_exit, DWORD wait_hint) {
    g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_status.dwCurrentState = state;
    g_status.dwControlsAccepted = (state == SERVICE_START_PENDING) ? 0 : SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
    g_status.dwWin32ExitCode = win32_exit;
    g_status.dwServiceSpecificExitCode = 0;
    g_status.dwCheckPoint = 0;
    g_status.dwWaitHint = wait_hint;
    SetServiceStatus(g_status_handle, &g_status);
}

static int build_paths(wchar_t *rsync, size_t rcap, wchar_t *config, size_t ccap, wchar_t *workdir, size_t wcap) {
    wchar_t self[32768];
    DWORD n = GetModuleFileNameW(NULL, self, 32768);
    if (!n || n >= 32768) return 0;
    wchar_t *slash = wcsrchr(self, L'\\');
    if (!slash) return 0;
    *slash = 0;
    wcscpy_s(workdir, wcap, self);
    swprintf_s(rsync, rcap, L"%s\\rsync.exe", self);

    wchar_t pd[32768];
    DWORD got = GetEnvironmentVariableW(L"ProgramData", pd, 32768);
    if (!got || got >= 32768) return 0;
    swprintf_s(config, ccap, L"%s\\Rsync\\rsyncd.conf", pd);
    return 1;
}

static DWORD spawn_daemon(void) {
    wchar_t rsync[32768], config[32768], workdir[32768];
    if (!build_paths(rsync, 32768, config, 32768, workdir, 32768)) return ERROR_PATH_NOT_FOUND;
    if (GetFileAttributesW(config) == INVALID_FILE_ATTRIBUTES) return ERROR_FILE_NOT_FOUND;

    wchar_t cmd[65536];
    swprintf_s(cmd, 65536, L"\"%s\" --daemon --no-detach --config=\"%s\"", rsync, config);

    STARTUPINFOW si; PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si)); ZeroMemory(&pi, sizeof(pi)); si.cb = sizeof(si);
    if (!CreateProcessW(rsync, cmd, NULL, NULL, TRUE, CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP, NULL, workdir, &si, &pi))
        return GetLastError();
    CloseHandle(pi.hThread);

    g_job = CreateJobObjectW(NULL, NULL);
    if (g_job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
        ZeroMemory(&info, sizeof(info));
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(g_job, JobObjectExtendedLimitInformation, &info, sizeof(info))
            || !AssignProcessToJobObject(g_job, pi.hProcess)) {
            CloseHandle(g_job);
            g_job = NULL;
        }
    }
    g_child = pi.hProcess;
    return ERROR_SUCCESS;
}

static DWORD WINAPI handler(DWORD control, DWORD event_type, LPVOID event_data, LPVOID context) {
    (void)event_type; (void)event_data; (void)context;
    if (control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_SHUTDOWN) {
        set_status(SERVICE_STOP_PENDING, NO_ERROR, 5000);
        if (g_stop_event) SetEvent(g_stop_event);
        return NO_ERROR;
    }
    return NO_ERROR;
}

static void WINAPI service_main(DWORD argc, LPWSTR *argv) {
    (void)argc; (void)argv;
    g_status_handle = RegisterServiceCtrlHandlerExW(L"RsyncDaemon", handler, NULL);
    if (!g_status_handle) return;
    ZeroMemory(&g_status, sizeof(g_status));
    set_status(SERVICE_START_PENDING, NO_ERROR, 5000);
    g_stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!g_stop_event) { set_status(SERVICE_STOPPED, GetLastError(), 0); return; }

    DWORD err = spawn_daemon();
    if (err != ERROR_SUCCESS) { set_status(SERVICE_STOPPED, err, 0); CloseHandle(g_stop_event); return; }
    set_status(SERVICE_RUNNING, NO_ERROR, 0);

    HANDLE waits[2] = { g_stop_event, g_child };
    DWORD w = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
    if (w == WAIT_OBJECT_0 && g_child) {
        if (g_job) TerminateJobObject(g_job, 0);
        else TerminateProcess(g_child, 0);
        WaitForSingleObject(g_child, 5000);
    }
    if (g_child) { CloseHandle(g_child); g_child = NULL; }
    if (g_job) { CloseHandle(g_job); g_job = NULL; }
    CloseHandle(g_stop_event); g_stop_event = NULL;
    set_status(SERVICE_STOPPED, NO_ERROR, 0);
}

int wmain(int argc, wchar_t **argv) {
    if (argc > 1 && _wcsicmp(argv[1], L"--console") == 0) {
        DWORD err = spawn_daemon();
        if (err != ERROR_SUCCESS) {
            fwprintf(stderr, L"rsync-service: daemon start failed, error %lu. Ensure %%ProgramData%%\\Rsync\\rsyncd.conf exists.\n", err);
            return (int)err;
        }
        WaitForSingleObject(g_child, INFINITE);
        DWORD ec = 1; GetExitCodeProcess(g_child, &ec); CloseHandle(g_child); g_child = NULL;
        if (g_job) { CloseHandle(g_job); g_job = NULL; }
        return (int)ec;
    }
    SERVICE_TABLE_ENTRYW table[] = {
        { L"RsyncDaemon", service_main },
        { NULL, NULL }
    };
    if (!StartServiceCtrlDispatcherW(table)) {
        DWORD err = GetLastError();
        if (err == ERROR_FAILED_SERVICE_CONTROLLER_CONNECT)
            fwprintf(stderr, L"rsync-service.exe is a Windows service host. Use --console for testing.\n");
        return (int)err;
    }
    return 0;
}
