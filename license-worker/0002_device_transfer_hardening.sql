ALTER TABLE devices ADD COLUMN lease_offline_until INTEGER NOT NULL DEFAULT 0;
ALTER TABLE devices ADD COLUMN slot_reusable_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE devices ADD COLUMN deactivated_at INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_devices_license_slot
ON devices(license_id, status, slot_reusable_at);

CREATE INDEX IF NOT EXISTS idx_devices_license_created
ON devices(license_id, created_at);
