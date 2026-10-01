ALTER TABLE licenses ADD COLUMN license_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_licenses_license_key_plaintext
ON licenses(license_key) WHERE license_key IS NOT NULL;

ALTER TABLE physical_devices ADD COLUMN serial_plaintext TEXT;

