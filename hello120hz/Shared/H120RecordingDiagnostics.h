#ifndef H120_RECORDING_DIAGNOSTICS_H
#define H120_RECORDING_DIAGNOSTICS_H
#include <stdint.h>
#include <dispatch/dispatch.h>
#ifdef __cplusplus
extern "C" {
#endif
#define H120_DIAGNOSTIC_VERSION 50904u
#define H120_RECORDING_LOG_DIRECTORY "/var/mobile/Library/Logs/Hello120Hz"
#define H120_RECORDING_LOG_PATH H120_RECORDING_LOG_DIRECTORY "/recording.jsonl"
/* Numeric state only; no media, bundle identifiers or user content. */
void H120DiagnosticStart(void);
void H120DiagnosticUpdate(unsigned hooks, int active, int preferencesReadable);
void H120DiagnosticLogError(int error);
uint64_t H120DiagnosticState(void);
int H120DiagnosticOpenLogAt(const char *directory, const char *path, int *error);
void H120DiagnosticProbe(double timeout, void (^completion)(uint64_t state, unsigned transportStatus));
#ifdef __cplusplus
}
#endif
#endif
