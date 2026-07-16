CREATE TABLE IF NOT EXISTS licenses (
  id TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active',
  max_devices INTEGER NOT NULL DEFAULT 1,
  features_json TEXT NOT NULL DEFAULT '["automation","stream","script","admin","shell"]',
  expires_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  license_id TEXT NOT NULL,
  device_key_hash TEXT NOT NULL,
  public_jwk TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  UNIQUE(license_id, device_key_hash)
);

CREATE INDEX IF NOT EXISTS idx_devices_license_status
ON devices(license_id, status);

CREATE TABLE IF NOT EXISTS activation_challenges (
  id TEXT PRIMARY KEY,
  license_id TEXT NOT NULL,
  device_key_hash TEXT NOT NULL,
  challenge TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_challenges_expiry
ON activation_challenges(expires_at);
