// Dock-only restore capacity. The delegate selector is declared by the iOS 16
// SBHIconStateUnarchiverDelegate protocol. The getter is a second, independent
// capability: require its real Q ABI rather than inferring a folder identity.
// iOS 17.6 disassembly corroborates ordering, NOT iOS 16.2 device validation.
static unsigned long long (*SBCPUPeachDockOriginalRestoreMaximum)(id, SEL);
static unsigned long long (*SBCPUPeachDockOriginalRestoreDelegateMaximum)(id, SEL, id);
static unsigned long long SBCPUPeachDockHookRestoreMaximum(id self, SEL cmd) {
    unsigned long long stock = SBCPUPeachDockOriginalRestoreMaximum(self, cmd);
    return MAX(stock, SBCPUPeachDockMaximumDockIcons);
}
static unsigned long long SBCPUPeachDockHookRestoreDelegateMaximum(id self, SEL cmd, id unarchiver) {
    unsigned long long stock = SBCPUPeachDockOriginalRestoreDelegateMaximum(self, cmd, unarchiver);
    return MAX(stock, SBCPUPeachDockMaximumDockIcons);
}
static BOOL SBCPUPeachDockRestoreReady(void) {
    Class model = objc_getClass("SBHIconModel");
    // The delegate runs before constructing/filling the Dock list. Ordinary
    // list-model initializers and non-Dock unarchive paths are not changed.
    return SBCPUPeachDockCapacityMethod(model, "maxIconCountForDock", "Q@:") &&
        SBCPUPeachDockCapacityMethod(model, "maxIconCountForDockForIconStateUnarchiver:", "Q@:@");
}
static void SBCPUPeachDockInstallRestore(void) {
    if (!SBCPUPeachDockRestoreReady()) return;
    Class model = objc_getClass("SBHIconModel");
    MSHookMessageEx(model, sel_registerName("maxIconCountForDock"),
        (IMP)SBCPUPeachDockHookRestoreMaximum, (IMP *)&SBCPUPeachDockOriginalRestoreMaximum);
    MSHookMessageEx(model, sel_registerName("maxIconCountForDockForIconStateUnarchiver:"),
        (IMP)SBCPUPeachDockHookRestoreDelegateMaximum, (IMP *)&SBCPUPeachDockOriginalRestoreDelegateMaximum);
}
