#import <Foundation/Foundation.h>

// 5.04 diagnostic: active-residency-weighted P-core MHz, or 0 (unavailable).
// Nonblocking; called by existing low-frequency refresh only. No private API on caller.
FOUNDATION_EXPORT double SBCPUReadPcoreFrequency(void);
