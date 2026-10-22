/* PartSieve Native platform adapter, Apache-2.0.
 * Syscalls only: policy, limits, JSON and publication orchestration are MoonBit.
 * Paths are UTF-8 NUL-terminated buffers validated by the MoonBit caller.
 */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include "moonbit.h"
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <fcntl.h>
#ifdef _WIN32
#include <windows.h>
#include <sddl.h>
#include <io.h>
#pragma comment(lib, "advapi32.lib")
#else
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#include <time.h>
#endif

static char ps_error_text[128];
static int ps_error(void) {
#ifdef _WIN32
  snprintf(ps_error_text, sizeof(ps_error_text), "native filesystem/process error (%lu/%d)", GetLastError(), errno);
#else
  snprintf(ps_error_text, sizeof(ps_error_text), "native filesystem/process error (%d)", errno);
#endif
  return -1;
}
static moonbit_bytes_t ps_bytes(const char *p, int n) {
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  if (n) memcpy(out, p, n);
  return out;
}
MOONBIT_FFI_EXPORT moonbit_bytes_t ps_last_error(void) {
  return ps_bytes(ps_error_text, (int)strlen(ps_error_text));
}
#ifdef _WIN32
static wchar_t *ps_wide(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
  if (!n) return NULL;
  wchar_t *out = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
  if (!out || !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, out, n)) { free(out); return NULL; }
  return out;
}
static moonbit_bytes_t ps_utf8(const wchar_t *s) {
  int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, NULL, 0, NULL, NULL);
  if (!n) { ps_error(); return ps_bytes("", 0); }
  moonbit_bytes_t out = moonbit_make_bytes(n - 1, 0);
  char *tmp = (char *)malloc(n);
  if (!tmp) { ps_error(); return ps_bytes("", 0); }
  WideCharToMultiByte(CP_UTF8, 0, s, -1, tmp, n, NULL, NULL);
  memcpy(out, tmp, n - 1); free(tmp); return out;
}
#endif
MOONBIT_FFI_EXPORT int ps_windows(void) {
#ifdef _WIN32
  return 1;
#else
  return 0;
#endif
}
MOONBIT_FFI_EXPORT int ps_open_read(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *w = ps_wide((const char *)path);
  if (!w) return ps_error();
  HANDLE h = CreateFileW(w, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, NULL);
  free(w);
  if (h == INVALID_HANDLE_VALUE) return ps_error();
  BY_HANDLE_FILE_INFORMATION info;
  if (GetFileType(h) != FILE_TYPE_DISK || !GetFileInformationByHandle(h, &info) ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) {
    CloseHandle(h); return ps_error();
  }
  int fd = _open_osfhandle((intptr_t)h, _O_RDONLY | _O_BINARY);
  if (fd < 0) { CloseHandle(h); return ps_error(); }
  return fd;
#else
  int fd = open((const char *)path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW);
  if (fd < 0) return ps_error();
  struct stat info;
  if (fstat(fd, &info) || !S_ISREG(info.st_mode)) { close(fd); return ps_error(); }
  return fd;
#endif
}
MOONBIT_FFI_EXPORT int ps_open_new(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *w = ps_wide((const char *)path);
  if (!w) return ps_error();
  HANDLE h = CreateFileW(w, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
  free(w);
  if (h == INVALID_HANDLE_VALUE) return ps_error();
  int fd = _open_osfhandle((intptr_t)h, _O_WRONLY | _O_BINARY);
  if (fd < 0) { CloseHandle(h); return ps_error(); }
  return fd;
#else
  int fd = open((const char *)path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  return fd < 0 ? ps_error() : fd;
#endif
}
MOONBIT_FFI_EXPORT int64_t ps_size(int fd) {
#ifdef _WIN32
  struct _stat64 s;
  return _fstat64(fd, &s) ? ps_error() : s.st_size;
#else
  struct stat s;
  return fstat(fd, &s) ? ps_error() : s.st_size;
#endif
}
MOONBIT_FFI_EXPORT int ps_read(int fd, moonbit_bytes_t buffer, int off, int count) {
#ifdef _WIN32
  int n = _read(fd, buffer + off, count);
#else
  int n; do { n = (int)read(fd, buffer + off, count); } while (n < 0 && errno == EINTR);
#endif
  return n < 0 ? ps_error() : n;
}
MOONBIT_FFI_EXPORT int ps_write(int fd, moonbit_bytes_t buffer, int off, int count) {
#ifdef _WIN32
  int n = _write(fd, buffer + off, count);
#else
  int n; do { n = (int)write(fd, buffer + off, count); } while (n < 0 && errno == EINTR);
#endif
  return n < 0 ? ps_error() : n;
}
MOONBIT_FFI_EXPORT int ps_sync(int fd) {
#ifdef _WIN32
  return _commit(fd) ? ps_error() : 0;
#else
  return fsync(fd) ? ps_error() : 0;
#endif
}
MOONBIT_FFI_EXPORT int ps_close(int fd) {
#ifdef _WIN32
  return _close(fd) ? ps_error() : 0;
#else
  return close(fd) ? ps_error() : 0;
#endif
}
MOONBIT_FFI_EXPORT int ps_exists(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *w = ps_wide((char *)path); if (!w) return ps_error();
  DWORD attrs = GetFileAttributesW(w); free(w);
  if (attrs != INVALID_FILE_ATTRIBUTES) return 1;
  DWORD e = GetLastError();
  return e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND ? 0 : ps_error();
#else
  struct stat s; if (!lstat((char *)path, &s)) return 1;
  return errno == ENOENT || errno == ENOTDIR ? 0 : ps_error();
#endif
}
MOONBIT_FFI_EXPORT int ps_link(moonbit_bytes_t source, moonbit_bytes_t target) {
#ifdef _WIN32
  wchar_t *s = ps_wide((char *)source), *t = ps_wide((char *)target);
  int ok = s && t && CreateHardLinkW(t, s, NULL); free(s); free(t);
  return ok ? 0 : ps_error();
#else
  return link((char *)source, (char *)target) ? ps_error() : 0;
#endif
}
MOONBIT_FFI_EXPORT int ps_unlink(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *w = ps_wide((char *)path); if (!w) return ps_error();
  int ok = DeleteFileW(w); free(w); return ok ? 0 : ps_error();
#else
  return unlink((char *)path) ? ps_error() : 0;
#endif
}
MOONBIT_FFI_EXPORT int ps_same_file(moonbit_bytes_t source, moonbit_bytes_t target) {
#ifdef _WIN32
  wchar_t *s = ps_wide((char *)source), *t = ps_wide((char *)target);
  if (!s || !t) { free(s); free(t); return 0; }
  HANDLE a = CreateFileW(s, FILE_READ_ATTRIBUTES, 7, NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  HANDLE b = CreateFileW(t, FILE_READ_ATTRIBUTES, 7, NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  free(s); free(t);
  BY_HANDLE_FILE_INFORMATION x, y;
  int ok = a != INVALID_HANDLE_VALUE && b != INVALID_HANDLE_VALUE &&
    GetFileInformationByHandle(a, &x) && GetFileInformationByHandle(b, &y) &&
    !(y.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) && x.dwVolumeSerialNumber == y.dwVolumeSerialNumber &&
    x.nFileIndexHigh == y.nFileIndexHigh && x.nFileIndexLow == y.nFileIndexLow;
  if (a != INVALID_HANDLE_VALUE) CloseHandle(a);
  if (b != INVALID_HANDLE_VALUE) CloseHandle(b);
  return ok;
#else
  struct stat a,b;
  return !lstat((char *)source,&a) && !lstat((char *)target,&b) && S_ISREG(b.st_mode) && a.st_dev == b.st_dev && a.st_ino == b.st_ino;
#endif
}
MOONBIT_FFI_EXPORT int ps_mkdir_private(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *w = ps_wide((char *)path); if (!w) return ps_error();
  HANDLE token = NULL; DWORD size = 0; PTOKEN_USER user = NULL;
  LPWSTR sid = NULL; PSECURITY_DESCRIPTOR sd = NULL; wchar_t sddl[256];
  int ok = 0;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    GetTokenInformation(token, TokenUser, NULL, 0, &size);
    user = (PTOKEN_USER)malloc(size);
    if (user && GetTokenInformation(token, TokenUser, user, size, &size) && ConvertSidToStringSidW(user->User.Sid, &sid)) {
      swprintf(sddl, 256, L"D:P(A;;FA;;;%ls)", sid);
      if (ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, SDDL_REVISION_1, &sd, NULL)) {
        SECURITY_ATTRIBUTES sa = {sizeof(sa), sd, FALSE}; ok = CreateDirectoryW(w, &sa);
      }
    }
  }
  if (token) CloseHandle(token); if (sid) LocalFree(sid); if (sd) LocalFree(sd);
  free(user); free(w); return ok ? 0 : ps_error();
#else
  return mkdir((char *)path, 0700) ? ps_error() : 0;
#endif
}
MOONBIT_FFI_EXPORT int ps_rmdir(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *w = ps_wide((char *)path); if (!w) return ps_error();
  int ok = RemoveDirectoryW(w); free(w); return ok ? 0 : ps_error();
#else
  return rmdir((char *)path) ? ps_error() : 0;
#endif
}
MOONBIT_FFI_EXPORT moonbit_bytes_t ps_temp_root(void) {
#ifdef _WIN32
  wchar_t w[32768]; DWORD n=GetTempPathW(32768,w);
  if (!n || n >= 32768) { ps_error(); return ps_bytes("",0); } return ps_utf8(w);
#else
  const char *p=getenv("TMPDIR"); if (!p || !*p) p="/tmp"; return ps_bytes(p,(int)strlen(p));
#endif
}
MOONBIT_FFI_EXPORT moonbit_bytes_t ps_absolute(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *w=ps_wide((char *)path), result[32768];
  if (!w) { ps_error(); return ps_bytes("",0); }
  DWORD n=GetFullPathNameW(w,32768,result,NULL); free(w);
  if (!n || n>=32768) { ps_error(); return ps_bytes("",0); }
  return ps_utf8(result);
#else
  const char *p=(char *)path; char cwd[4096], out[8192];
  if (*p=='/') return ps_bytes(p,(int)strlen(p));
  if (!getcwd(cwd,sizeof(cwd))) { ps_error(); return ps_bytes("",0); }
  int n=snprintf(out,sizeof(out),"%s/%s",cwd,p);
  if (n<0 || n >= (int)sizeof(out)) { ps_error(); return ps_bytes("",0); }
  return ps_bytes(out,n);
#endif
}
MOONBIT_FFI_EXPORT moonbit_bytes_t ps_self(void) {
#ifdef _WIN32
  wchar_t w[32768]; DWORD n=GetModuleFileNameW(NULL,w,32768);
  if (!n || n>=32768) { ps_error(); return ps_bytes("",0); } return ps_utf8(w);
#else
  char out[4096]; ssize_t n=readlink("/proc/self/exe",out,sizeof(out));
  if (n<0 || n>=(ssize_t)sizeof(out)) { ps_error(); return ps_bytes("",0); }
  return ps_bytes(out,(int)n);
#endif
}
MOONBIT_FFI_EXPORT int64_t ps_millis(void) {
#ifdef _WIN32
  return (int64_t)GetTickCount64();
#else
  struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (int64_t)t.tv_sec*1000+t.tv_nsec/1000000;
#endif
}
MOONBIT_FFI_EXPORT void ps_pause(int ms) {
#ifdef _WIN32
  Sleep(ms);
#else
  struct timespec t={ms/1000,(ms%1000)*1000000L}; while(nanosleep(&t,&t) && errno==EINTR) {}
#endif
}
typedef struct {
  int code;
#ifdef _WIN32
  HANDLE process, job, pipe;
#else
  pid_t pid; int pipe;
#endif
} ps_process;
MOONBIT_FFI_EXPORT int ps_null(void *p) { return p==NULL; }
MOONBIT_FFI_EXPORT ps_process *ps_spawn(moonbit_bytes_t executable, moonbit_bytes_t block) {
  /* Arguments are NUL-delimited bytes; no shell or executable search. */
  const char *args[32]; int count=0, pos=0, length=Moonbit_array_length(block);
  while (pos<length && count<32) {
    const char *arg=(char *)block+pos; size_t n=strlen(arg);
    if (pos+(int)n>=length) { ps_error(); return NULL; }
    args[count++]=arg; pos+=(int)n+1;
  }
  if (pos!=length || count>=32) { ps_error(); return NULL; }
  ps_process *p=(ps_process *)calloc(1,sizeof(ps_process)); if (!p) { ps_error(); return NULL; }
  p->code=-1;
#ifdef _WIN32
  wchar_t *exe=ps_wide((char *)executable), command[32768]; size_t at=0;
  if (!exe) goto win_fail;
  /* Quote each argument according to CommandLineToArgv/CRT rules. */
  for (int i=-1;i<count;i++) {
    wchar_t *a=i<0?exe:ps_wide(args[i]); if (!a) goto win_fail;
    if (at>32760) { if(i>=0)free(a); goto win_fail; }
    if(at)command[at++]=L' '; command[at++]=L'"';
    size_t slashes=0;
    for(size_t k=0;;k++) {
      wchar_t c=a[k]; if(c==L'\\') { slashes++; continue; }
      size_t n= c==L'"'||c==0?slashes*2:slashes;
      if(at+n+3>=32768) { if(i>=0)free(a); goto win_fail; }
      while(n--)command[at++]=L'\\'; slashes=0;
      if(!c)break; if(c==L'"')command[at++]=L'\\'; command[at++]=c;
    }
    command[at++]=L'"'; if(i>=0)free(a);
  }
  command[at]=0;
  SECURITY_ATTRIBUTES sa={sizeof(sa),NULL,TRUE}; HANDLE writer=NULL;
  if(!CreatePipe(&p->pipe,&writer,&sa,0))goto win_fail;
  SetHandleInformation(p->pipe,HANDLE_FLAG_INHERIT,0);
  HANDLE nullh=CreateFileW(L"NUL",GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,&sa,OPEN_EXISTING,0,NULL);
  p->job=CreateJobObjectW(NULL,NULL);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limit; memset(&limit,0,sizeof(limit));
  limit.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if(!p->job || !SetInformationJobObject(p->job,JobObjectExtendedLimitInformation,&limit,sizeof(limit))) {
    CloseHandle(writer); if(nullh!=INVALID_HANDLE_VALUE)CloseHandle(nullh); goto win_fail;
  }
  STARTUPINFOW startup; PROCESS_INFORMATION info; memset(&startup,0,sizeof(startup));
  startup.cb=sizeof(startup); startup.dwFlags=STARTF_USESTDHANDLES;
  startup.hStdInput=nullh; startup.hStdError=nullh; startup.hStdOutput=writer;
  int ok=CreateProcessW(exe,command,NULL,NULL,TRUE,CREATE_NO_WINDOW|CREATE_SUSPENDED,NULL,NULL,&startup,&info);
  CloseHandle(writer); if(nullh!=INVALID_HANDLE_VALUE)CloseHandle(nullh);
  if(!ok)goto win_fail;
  if(!AssignProcessToJobObject(p->job,info.hProcess)) {
    TerminateProcess(info.hProcess,4); WaitForSingleObject(info.hProcess,INFINITE);
    CloseHandle(info.hThread); CloseHandle(info.hProcess); goto win_fail;
  }
  p->process=info.hProcess; ResumeThread(info.hThread); CloseHandle(info.hThread); free(exe); return p;
win_fail:
  ps_error(); if(p->pipe)CloseHandle(p->pipe); if(p->job)CloseHandle(p->job);
  free(exe); free(p); return NULL;
#else
  int pipes[2]; if(pipe(pipes))goto posix_fail;
  fcntl(pipes[0],F_SETFD,FD_CLOEXEC); fcntl(pipes[1],F_SETFD,FD_CLOEXEC);
  fcntl(pipes[0],F_SETFL,O_NONBLOCK);
  pid_t pid=fork();
  if(pid<0) { close(pipes[0]);close(pipes[1]);goto posix_fail; }
  if(pid==0) {
    setpgid(0,0); dup2(pipes[1],STDOUT_FILENO); close(pipes[0]);close(pipes[1]);
    int n=open("/dev/null",O_RDWR); if(n>=0){dup2(n,STDIN_FILENO);dup2(n,STDERR_FILENO);if(n>2)close(n);}
    char *argv[34];argv[0]=(char *)executable;for(int i=0;i<count;i++)argv[i+1]=(char *)args[i];argv[count+1]=NULL;
    execv((char *)executable,argv);_exit(4);
  }
  close(pipes[1]);setpgid(pid,pid);p->pid=pid;p->pipe=pipes[0];return p;
posix_fail:
  ps_error();free(p);return NULL;
#endif
}
MOONBIT_FFI_EXPORT int ps_process_read(ps_process *p,moonbit_bytes_t buffer,int count) {
#ifdef _WIN32
  DWORD available=0,n=0;
  if(!PeekNamedPipe(p->pipe,NULL,0,NULL,&available,NULL))return GetLastError()==ERROR_BROKEN_PIPE?-2:ps_error();
  if(!available)return 0; if(available>(DWORD)count)available=count;
  return ReadFile(p->pipe,buffer,available,&n,NULL)?(int)n:ps_error();
#else
  int n=(int)read(p->pipe,buffer,count);
  if(n==0)return -2;
  if(n<0 && (errno==EAGAIN || errno==EWOULDBLOCK || errno==EINTR))return 0;
  return n<0?ps_error():n;
#endif
}
MOONBIT_FFI_EXPORT int ps_process_poll(ps_process *p) {
  if(p->code>=0)return p->code;
#ifdef _WIN32
  if(WaitForSingleObject(p->process,0)==WAIT_TIMEOUT)return -1;
  DWORD code=4;if(!GetExitCodeProcess(p->process,&code))return 4;p->code=code<=255?(int)code:4;
#else
  /* Retain the zombie until close: its PID cannot be recycled before group cleanup. */
  siginfo_t info; memset(&info,0,sizeof(info));
  int n=waitid(P_PID,(id_t)p->pid,&info,WEXITED|WNOHANG|WNOWAIT);
  if((n<0&&errno==EINTR) || (n==0&&!info.si_pid))return -1;
  p->code=n<0?4:info.si_code==CLD_EXITED?info.si_status:4;
#endif
  return p->code;
}
MOONBIT_FFI_EXPORT void ps_process_close(ps_process *p) {
#ifdef _WIN32
  if(p->job)CloseHandle(p->job); /* terminate running worker descendants */
  if(p->process) { WaitForSingleObject(p->process,INFINITE);CloseHandle(p->process); }
  if(p->pipe)CloseHandle(p->pipe);
#else
  kill(-p->pid,SIGKILL);
  kill(p->pid,SIGKILL);
  {int s;while(waitpid(p->pid,&s,0)<0&&errno==EINTR){}}
  close(p->pipe);
#endif
  free(p);
}

MOONBIT_FFI_EXPORT void ps_warning(moonbit_bytes_t message) {
  fputs("PartSieve cleanup warning: ", stderr);
  fwrite(message, 1, Moonbit_array_length(message), stderr);
  fputc('\n', stderr);
}
