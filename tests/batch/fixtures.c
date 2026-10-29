/* Test-only filesystem fixtures, never part of the library adapter. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include "moonbit.h"
#ifdef _WIN32
#include <windows.h>
MOONBIT_FFI_EXPORT int ps_batch_fixture(moonbit_bytes_t source, moonbit_bytes_t target, int kind) {
  if (kind == 2) return 0; /* Named pipes are not ordinary directory entries here. */
  wchar_t a[32768], b[32768];
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)source, -1, a, 32768) ||
      !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)target, -1, b, 32768)) return 0;
  DWORD flags = kind == 1 ? SYMBOLIC_LINK_FLAG_DIRECTORY : 0;
  return (CreateSymbolicLinkW(b, a, flags | 2) || CreateSymbolicLinkW(b, a, flags)) ? 1 : 0;
}
#else
#include <unistd.h>
#include <sys/stat.h>
MOONBIT_FFI_EXPORT int ps_batch_fixture(moonbit_bytes_t source, moonbit_bytes_t target, int kind) {
  return (kind == 2 ? mkfifo((const char *)target, 0600) : symlink((const char *)source, (const char *)target)) == 0;
}
#endif
