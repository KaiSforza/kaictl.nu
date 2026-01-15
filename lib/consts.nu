# Default duration for op cli to cache credentials without the desktop app
export const C_DUR: duration = 30min
# Old enough to invalidate the cache
export const C_DEF: datetime = 2000-01-01
# Where to store the cached files in `cache read`
export const D_CACHE: path = $nu.cache-dir
export const LP_SEP: string = "|"
export const AWS_ACCOUNT_OP_URL: string = "op://Personal/aws" # Must be 'op://...'

export const CNF_DB = ["~" ".cache" "nix-index-not-found"] | path join | path expand
export const DB_NIX_S = ["~" ".cache" "nix-s" "nix-search.db"] | path join | path expand
