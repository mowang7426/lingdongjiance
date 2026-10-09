# SBCPU + Insulation 0.1.38.1 integration

This revision integrates the actual Insulation 0.1.38.1 runtime components from the supplied DEB into the SBCPU package and places the original Insulation settings in SBCPU's existing root preferences page before the MoWang source row.

The five visible settings match the supplied Insulation page: CPU mode, prevent thermal dimming, suppress thermometer notifications, disable pocket high-temperature behavior, and lock sunlight behavior. The original preference domain (`com.be-huge.insulation-prefs`) and original keys are retained so the supplied Insulation binary reads the same settings. The original `insulation.dylib`, its thermalmonitord filter plist, Control Center bundle, and `insulationctl` are staged by the SBCPU Makefile.

This is a source-level package integration. It has not been built with Theos or tested on a jailbroken device in this environment. The original Insulation binary's injection compatibility and each runtime behavior must still be verified on the target iOS 17 jailbreak. Do not use thermal-warning suppression as a substitute for hardware thermal protection.
