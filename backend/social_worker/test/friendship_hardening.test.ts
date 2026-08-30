        import { describe, expect, it } from 'vitest';

        import {
          friendRequestConflict,
          friendshipPresentationStatus,
        } from '../src/friend_notifications';

        describe('friendship state hardening', () => {
          it('keeps pending direction explicit', () => {
            const outgoing = { requester_id: 'a', status: 'pending' };
            const incoming = { requester_id: 'b', status: 'pending' };

            expect(friendshipPresentationStatus(outgoing, 'a')).toBe(
              'outgoing_pending',
            );
            expect(friendshipPresentationStatus(incoming, 'a')).toBe(
              'incoming_pending',
            );
          });

          it('rejects duplicate outgoing requests without changing direction', () => {
            expect(
              friendRequestConflict(
                { requester_id: 'a', status: 'pending' },
                'a',
                'b',
              ),
            ).toMatchObject({
              status: 409,
              code: 'friend_request_already_pending',
              friendshipStatus: 'outgoing_pending',
            });
          });

          it('rejects reverse pending requests without changing requester', () => {
            expect(
              friendRequestConflict(
                { requester_id: 'b', status: 'pending' },
                'a',
                'b',
              ),
            ).toMatchObject({
              status: 409,
              code: 'incoming_friend_request_pending',
              friendshipStatus: 'incoming_pending',
            });
          });

          it('rejects accepted and blocked relationships', () => {
            expect(
              friendRequestConflict(
                { requester_id: 'a', status: 'accepted' },
                'a',
                'b',
              ),
            ).toMatchObject({ status: 409, code: 'already_friends' });
            expect(
              friendRequestConflict(
                { requester_id: 'a', status: 'blocked' },
                'a',
                'b',
              ),
            ).toMatchObject({ status: 403, code: 'player_unavailable' });
          });

          it('allows a declined relationship to be requested again', () => {
            expect(
              friendRequestConflict(
                { requester_id: 'b', status: 'declined' },
                'a',
                'b',
              ),
            ).toBeNull();
          });
        });
