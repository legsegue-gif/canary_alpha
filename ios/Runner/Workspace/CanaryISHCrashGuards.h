//
//  CanaryISHCrashGuards.h
//  Runner
//
//  Crash containment for the embedded iSH kernel. A guest crash must take
//  down at most the guest task thread, never the whole Flutter app.
//

#ifndef CanaryISHCrashGuards_h
#define CanaryISHCrashGuards_h

/// Install signal handlers that recover from guest JIT faults (SIGSEGV/
/// SIGBUS/SIGILL/SIGTRAP on iSH threads) and re-raise untouched on non-iSH
/// threads. Must be called before any guest code runs.
void CanaryISHInstallCrashGuards(void);

/// Point iSH's die() at a handler that parks the faulting thread instead
/// of abort()ing the entire app process.
void CanaryISHInstallDieGuard(void);

#endif /* CanaryISHCrashGuards_h */
