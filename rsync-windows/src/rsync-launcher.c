#define UNICODE
#define _UNICODE
#include <windows.h>
#include <wchar.h>
#include <stdio.h>
#include <stdlib.h>
#include <wctype.h>

static int is_drive_abs(const wchar_t *s) {
    return s && iswalpha(s[0]) && s[1] == L':' && (s[2] == L'\\' || s[2] == L'/');
}

static int is_unc(const wchar_t *s) {
    return s && s[0] == L'\\' && s[1] == L'\\';
}

static wchar_t *dup_w(const wchar_t *s) {
    size_t n = wcslen(s) + 1;
    wchar_t *p = (wchar_t*)calloc(n, sizeof(wchar_t));
    if (p) wcscpy_s(p, n, s);
    return p;
}

static wchar_t *win_to_cyg(const wchar_t *in) {
    if (!in) return NULL;
    if (wcsncmp(in, L"\\\\?\\UNC\\", 8) == 0) {
        const wchar_t *p = in + 8;
        size_t len = wcslen(p);
        wchar_t *out = (wchar_t*)calloc(len + 3, sizeof(wchar_t));
        if (!out) return NULL;
        out[0] = L'/'; out[1] = L'/';
        for (size_t i = 0; i < len; ++i) out[i + 2] = p[i] == L'\\' ? L'/' : p[i];
        return out;
    }
    if (wcsncmp(in, L"\\\\?\\", 4) == 0) in += 4;

    if (is_drive_abs(in)) {
        wchar_t drive = towlower(in[0]);
        const wchar_t *rest = in + 3;
        size_t len = wcslen(rest);
        const wchar_t prefix[] = L"/cygdrive/x/";
        wchar_t *out = (wchar_t*)calloc((sizeof(prefix)/sizeof(prefix[0])) + len + 2, sizeof(wchar_t));
        if (!out) return NULL;
        wcscpy_s(out, 14 + len, prefix);
        out[10] = drive;
        size_t pos = wcslen(out);
        for (size_t i = 0; i < len; ++i) out[pos + i] = rest[i] == L'\\' ? L'/' : rest[i];
        return out;
    }

    if (is_unc(in)) {
        const wchar_t *p = in + 2;
        size_t len = wcslen(p);
        wchar_t *out = (wchar_t*)calloc(len + 3, sizeof(wchar_t));
        if (!out) return NULL;
        out[0] = L'/'; out[1] = L'/';
        for (size_t i = 0; i < len; ++i) out[i + 2] = p[i] == L'\\' ? L'/' : p[i];
        return out;
    }
    return dup_w(in);
}

static wchar_t *translate_arg(const wchar_t *arg) {
    if (!arg) return NULL;
    if (is_drive_abs(arg) || is_unc(arg) || wcsncmp(arg, L"\\\\?\\", 4) == 0)
        return win_to_cyg(arg);

    if (wcsncmp(arg, L"--", 2) == 0) {
        const wchar_t *eq = wcschr(arg, L'=');
        if (eq && (is_drive_abs(eq + 1) || is_unc(eq + 1) || wcsncmp(eq + 1, L"\\\\?\\", 4) == 0)) {
            size_t keylen = (size_t)(eq - arg + 1);
            wchar_t *converted = win_to_cyg(eq + 1);
            if (!converted) return NULL;
            size_t total = keylen + wcslen(converted) + 1;
            wchar_t *out = (wchar_t*)calloc(total, sizeof(wchar_t));
            if (!out) { free(converted); return NULL; }
            wcsncpy_s(out, total, arg, keylen);
            wcscat_s(out, total, converted);
            free(converted);
            return out;
        }
    }
    return dup_w(arg);
}

static int append_quoted(wchar_t **buf, size_t *cap, size_t *len, const wchar_t *arg) {
    int need_quotes = *arg == 0 || wcspbrk(arg, L" \t\n\v\"") != NULL;
    size_t worst = wcslen(arg) * 2 + 4;
    if (*len + worst + 1 > *cap) {
        size_t ncap = (*cap ? *cap : 256);
        while (ncap < *len + worst + 1) ncap *= 2;
        wchar_t *nb = (wchar_t*)realloc(*buf, ncap * sizeof(wchar_t));
        if (!nb) return 0;
        *buf = nb; *cap = ncap;
    }
    if (!need_quotes) {
        size_t n = wcslen(arg);
        memcpy(*buf + *len, arg, n * sizeof(wchar_t));
        *len += n; (*buf)[*len] = 0;
        return 1;
    }
    (*buf)[(*len)++] = L'"';
    size_t slashes = 0;
    for (const wchar_t *p = arg; ; ++p) {
        if (*p == L'\\') { slashes++; continue; }
        if (*p == L'"') {
            for (size_t i = 0; i < slashes * 2 + 1; ++i) (*buf)[(*len)++] = L'\\';
            (*buf)[(*len)++] = L'"'; slashes = 0; continue;
        }
        if (*p == 0) {
            for (size_t i = 0; i < slashes * 2; ++i) (*buf)[(*len)++] = L'\\';
            break;
        }
        for (size_t i = 0; i < slashes; ++i) (*buf)[(*len)++] = L'\\';
        slashes = 0; (*buf)[(*len)++] = *p;
    }
    (*buf)[(*len)++] = L'"'; (*buf)[*len] = 0;
    return 1;
}

static int has_config_arg(int argc, wchar_t **argv) {
    for (int i = 1; i < argc; ++i) {
        if (_wcsicmp(argv[i], L"--config") == 0 || wcsncmp(argv[i], L"--config=", 9) == 0)
            return 1;
    }
    return 0;
}

static int has_daemon_arg(int argc, wchar_t **argv) {
    for (int i = 1; i < argc; ++i) if (_wcsicmp(argv[i], L"--daemon") == 0) return 1;
    return 0;
}

int wmain(int argc, wchar_t **argv) {
    wchar_t self[MAX_PATH * 4];
    DWORD n = GetModuleFileNameW(NULL, self, (DWORD)(sizeof(self)/sizeof(self[0])));
    if (!n || n >= sizeof(self)/sizeof(self[0])) {
        fwprintf(stderr, L"rsync launcher: cannot determine executable path (error %lu)\n", GetLastError());
        return 127;
    }
    wchar_t *slash = wcsrchr(self, L'\\');
    if (!slash) return 127;
    *(slash + 1) = 0;

    wchar_t core[MAX_PATH * 4];
    swprintf_s(core, sizeof(core)/sizeof(core[0]), L"%srsync-core.exe", self);
    DWORD attr = GetFileAttributesW(core);
    if (attr == INVALID_FILE_ATTRIBUTES) {
        fwprintf(stderr, L"rsync launcher: missing %s\n", core);
        return 127;
    }

    wchar_t *cmd = NULL; size_t cap = 0, len = 0;
    if (!append_quoted(&cmd, &cap, &len, core)) return 125;

    for (int i = 1; i < argc; ++i) {
        wchar_t *t = translate_arg(argv[i]);
        if (!t) { free(cmd); return 125; }
        if (len + 2 >= cap) { cap = cap ? cap * 2 : 256; cmd = (wchar_t*)realloc(cmd, cap * sizeof(wchar_t)); if (!cmd) { free(t); return 125; } }
        cmd[len++] = L' '; cmd[len] = 0;
        if (!append_quoted(&cmd, &cap, &len, t)) { free(t); free(cmd); return 125; }
        free(t);
    }

    if (has_daemon_arg(argc, argv) && !has_config_arg(argc, argv)) {
        wchar_t programData[MAX_PATH * 4];
        DWORD got = GetEnvironmentVariableW(L"ProgramData", programData, (DWORD)(sizeof(programData)/sizeof(programData[0])));
        if (got && got < sizeof(programData)/sizeof(programData[0])) {
            wchar_t cfg[MAX_PATH * 4];
            swprintf_s(cfg, sizeof(cfg)/sizeof(cfg[0]), L"%s\\Rsync\\rsyncd.conf", programData);
            wchar_t *cyg = win_to_cyg(cfg);
            if (cyg) {
                wchar_t opt[MAX_PATH * 4 + 32];
                swprintf_s(opt, sizeof(opt)/sizeof(opt[0]), L"--config=%s", cyg);
                if (len + 2 >= cap) { cap *= 2; cmd = (wchar_t*)realloc(cmd, cap * sizeof(wchar_t)); if (!cmd) { free(cyg); return 125; } }
                cmd[len++] = L' '; cmd[len] = 0;
                if (!append_quoted(&cmd, &cap, &len, opt)) { free(cyg); free(cmd); return 125; }
                free(cyg);
            }
        }
    }

    STARTUPINFOW si; PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si)); ZeroMemory(&pi, sizeof(pi)); si.cb = sizeof(si);
    BOOL ok = CreateProcessW(core, cmd, NULL, NULL, TRUE, 0, NULL, self, &si, &pi);
    if (!ok) {
        fwprintf(stderr, L"rsync launcher: failed to start core (error %lu)\n", GetLastError());
        free(cmd); return 127;
    }
    free(cmd);
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD ec = 1;
    GetExitCodeProcess(pi.hProcess, &ec);
    CloseHandle(pi.hProcess);
    return (int)ec;
}
