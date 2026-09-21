ALTER TABLE activation_challenges ADD COLUMN activation_intent TEXT NOT NULL DEFAULT 'device_transfer';
ALTER TABLE activation_challenges ADD COLUMN hardware_fingerprints_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE activation_challenges ADD COLUMN hardware_claims_digest TEXT NOT NULL DEFAULT '';

ALTER TABLE devices ADD COLUMN physical_device_id TEXT;
ALTER TABLE devices ADD COLUMN bind_reason TEXT;
ALTER TABLE devices ADD COLUMN hardware_confidence TEXT;
ALTER TABLE devices ADD COLUMN hardware_policy_version INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS physical_devices (
    id TEXT PRIMARY KEY,
    license_id TEXT NOT NULL,
    udid_hmac TEXT,
    serial_hmac TEXT,
    mlb_hmac TEXT,
    ecid_hmac TEXT,
    first_seen_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    reset_count INTEGER NOT NULL DEFAULT 0,
    transfer_count INTEGER NOT NULL DEFAULT 0,
    risk_score INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active',
    FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_physical_devices_license_seen
ON physical_devices(license_id, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS idx_physical_devices_udid
ON physical_devices(udid_hmac);

CREATE INDEX IF NOT EXISTS idx_physical_devices_serial
ON physical_devices(serial_hmac);

CREATE INDEX IF NOT EXISTS idx_physical_devices_mlb
ON physical_devices(mlb_hmac);

CREATE INDEX IF NOT EXISTS idx_physical_devices_ecid
ON physical_devices(ecid_hmac);

CREATE UNIQUE INDEX IF NOT EXISTS idx_physical_devices_license_udid_unique
ON physical_devices(license_id, udid_hmac) WHERE udid_hmac IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_physical_devices_license_serial_unique
ON physical_devices(license_id, serial_hmac) WHERE serial_hmac IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_physical_devices_license_mlb_unique
ON physical_devices(license_id, mlb_hmac) WHERE mlb_hmac IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_physical_devices_license_ecid_unique
ON physical_devices(license_id, ecid_hmac) WHERE ecid_hmac IS NOT NULL;

CREATE TABLE IF NOT EXISTS license_device_events (
    id TEXT PRIMARY KEY,
    license_id TEXT NOT NULL,
    physical_device_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    decision_code TEXT NOT NULL,
    match_confidence TEXT NOT NULL,
    identifier_mask INTEGER NOT NULL,
    risk_score INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE,
    FOREIGN KEY (physical_device_id) REFERENCES physical_devices(id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_license_device_events_license_created
ON license_device_events(license_id, created_at DESC);
