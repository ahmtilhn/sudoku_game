-- Challenge lifecycle hardening.
"
    "UPDATE challenges
"
    "SET status = 'cancelled', updated_at = datetime('now')
"
    "WHERE status = 'pending'
"
    "  AND rowid NOT IN (
"
    "    SELECT MAX(rowid)
"
    "    FROM challenges
"
    "    WHERE status = 'pending'
"
    "    GROUP BY challenger_id, recipient_id
"
    "  );

"
    "CREATE UNIQUE INDEX IF NOT EXISTS challenges_unique_pending_direction_idx
"
    "  ON challenges(challenger_id, recipient_id)
"
    "  WHERE status = 'pending';
"
    