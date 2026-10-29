# Shared video encoding

Platform-independent PNG validation, timestamped frame persistence and VFR MP4 assembly. The bundled FFmpegKit C ABI uses VideoToolbox on the macOS host and never invokes a PATH encoder. Acquisition belongs to the target-platform packages; this package has no Marionette connection or Flutter rendering provider. It depends on platform contracts and native encoder dependencies only.
