PRAGMA foreign_keys = ON;

-- Career rewarded interstitials are optional after successful puzzles. Cap the
-- number of server reward preparations per UTC day to limit scripted farming.
CREATE TRIGGER cap_daily_career_reward_preparations
BEFORE INSERT ON reward_claims
WHEN NEW.reward_type = 'career_rewarded_ad'
  AND (
    SELECT COUNT(*) FROM reward_claims
    WHERE player_id = NEW.player_id
      AND reward_type = 'career_rewarded_ad'
      AND substr(prepared_at, 1, 10) = substr(NEW.prepared_at, 1, 10)
      AND status IN ('prepared', 'claimed')
  ) >= 20
BEGIN
  SELECT RAISE(ABORT, 'career_reward_daily_cap');
END;
