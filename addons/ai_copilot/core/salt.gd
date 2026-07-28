class_name AiCopilotSalt
extends RefCounted

static func ensure_salt() -> PackedByteArray:
	if FileAccess.file_exists(AiCopilotConst.SALT_FILE):
		var existing := FileAccess.get_file_as_bytes(AiCopilotConst.SALT_FILE)
		if existing.size() == 32:
			return existing
	var bytes := Crypto.new().generate_random_bytes(32)
	var f := FileAccess.open(AiCopilotConst.SALT_FILE, FileAccess.WRITE)
	if f == null:
		push_error("[ai_copilot] cannot open salt file (%d)" % FileAccess.get_open_error())
		return PackedByteArray()
	f.store_buffer(bytes)
	f.close()
	# Best-effort 0600 perms on Unix-like systems. Skipped on Windows (no chmod).
	var os_name := OS.get_name()
	if os_name == "macOS" or os_name == "Linux" or os_name == "FreeBSD" or os_name == "NetBSD" or os_name == "OpenBSD" or os_name == "BSD":
		OS.execute("chmod", ["0600", ProjectSettings.globalize_path(AiCopilotConst.SALT_FILE)])
	return bytes
