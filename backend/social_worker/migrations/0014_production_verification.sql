PRAGMA foreign_keys = ON;

ALTER TABLE reward_claims ADD COLUMN ssv_transaction_id TEXT;
ALTER TABLE reward_claims ADD COLUMN ssv_verified_at TEXT;
ALTER TABLE reward_claims ADD COLUMN ssv_ad_unit TEXT;
ALTER TABLE reward_claims ADD COLUMN ssv_reward_amount INTEGER;
ALTER TABLE reward_claims ADD COLUMN ssv_reward_item TEXT;

CREATE UNIQUE INDEX reward_claims_ssv_transaction_idx
  ON reward_claims(ssv_transaction_id)
  WHERE ssv_transaction_id IS NOT NULL;

CREATE INDEX reward_claims_ssv_token_idx
  ON reward_claims(player_id, verification_token, ssv_verified_at);

ALTER TABLE purchase_grants ADD COLUMN store_environment TEXT;
ALTER TABLE purchase_grants ADD COLUMN store_order_id TEXT;
ALTER TABLE purchase_grants ADD COLUMN consumed_at TEXT;
ALTER TABLE purchase_grants ADD COLUMN verification_source TEXT;

CREATE INDEX purchase_grants_store_order_idx
  ON purchase_grants(store_order_id)
  WHERE store_order_id IS NOT NULL;
