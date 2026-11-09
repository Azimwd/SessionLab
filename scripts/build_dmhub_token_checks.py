"""Build the DMHub token mod with ASCII-only Lua source and UTF-8 labels."""
from pathlib import Path

scripts = Path(__file__).resolve().parent
source = (scripts / "SessionLabTokenChecks_Source.lua").read_text(encoding="utf-8")
encoded = "".join(
    char if char.isascii() else "".join(f"\\{byte:03d}" for byte in char.encode("utf-8"))
    for char in source
)
(scripts / "SessionLabTokenChecks_Main.lua").write_text(encoded, encoding="ascii")
