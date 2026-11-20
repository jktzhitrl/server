// Rollenlogik analog zu lib/core/auth/permissions.dart (nur das hier Nötige).
export type Role = 'spectator' | 'player' | 'scorer' | 'director' | 'admin';
const ORDER: Role[] = ['spectator', 'player', 'scorer', 'director', 'admin'];

export const effectiveRole = (global: Role, inTournament?: Role | null): Role =>
  inTournament && ORDER.indexOf(inTournament) > ORDER.indexOf(global) ? inTournament : global;

export const canEnterScores = (role: Role) => ORDER.indexOf(role) >= ORDER.indexOf('scorer');
export const canConfirm = (role: Role) => ORDER.indexOf(role) >= ORDER.indexOf('director');
