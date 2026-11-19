-- CLA-141: when this Mac became active, for About > Activation ("Activated on 19 Nov 2026").
-- NULL: not active. A swap that turns the Mac off clears it; a new activation sets it again.
ALTER TABLE macs ADD COLUMN activated_at INTEGER;
-- Active Macs from before this migration: the time their last link was used, else NULL.
UPDATE macs SET activated_at = (
  SELECT MAX(used_at) FROM mails WHERE mails.device_hash = macs.device_hash AND mails.account_id = macs.account_id
) WHERE state = 'active';
