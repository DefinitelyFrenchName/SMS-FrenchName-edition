-- techfind_cfg.lua — config for techfind.lua (throw instrumentation; see its header).
-- Default: Venus throws Jupiter, Jupiter mashes HK gap-2 (techs on both clean and patched).
-- Set NOMASH=true to log the sampling schedule alone; SCRIPT_LO/HI to watch script ROM reads
-- (Venus hold script: 0xC16C53-0xC16CA2).
STATE = "venus_vs_jupiter_clean.mss"
MASH = 10
MASHGAP = 2
