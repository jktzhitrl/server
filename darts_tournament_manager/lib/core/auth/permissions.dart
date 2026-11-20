/// Rollen im System (aufsteigend nach Rechten).
enum Role { spectator, player, scorer, director, admin }

enum Permission {
  viewPublicTournament,
  joinTournament,
  viewOwnStats,
  createTournament,
  editTournament,
  manageParticipants,
  configureRules,
  runDraw,
  publishDraw,
  assignMatches,
  startMatch,
  enterScores,
  submitResult,
  confirmResult,
  correctResult,
  manageBoards,
  manageRoles,
  viewAuditLog,
}

const Map<Role, Set<Permission>> _matrix = {
  Role.spectator: {Permission.viewPublicTournament},
  Role.player: {
    Permission.viewPublicTournament,
    Permission.joinTournament,
    Permission.viewOwnStats,
  },
  Role.scorer: {
    Permission.viewPublicTournament,
    Permission.joinTournament,
    Permission.viewOwnStats,
    Permission.startMatch,
    Permission.enterScores,
    Permission.submitResult,
  },
  Role.director: {
    Permission.viewPublicTournament,
    Permission.joinTournament,
    Permission.viewOwnStats,
    Permission.startMatch,
    Permission.enterScores,
    Permission.submitResult,
    Permission.runDraw,
    Permission.publishDraw,
    Permission.assignMatches,
    Permission.confirmResult,
    Permission.correctResult,
    Permission.manageBoards,
    Permission.manageParticipants,
  },
  Role.admin: {...Permission.values},
};

/// Hat [role] das Recht [permission]?
bool can(Role role, Permission permission) => _matrix[role]!.contains(permission);

/// Höhere Rolle gewinnt (globale Rolle vs. Rolle im Turnier).
Role effectiveRole(Role global, Role? inTournament) {
  if (inTournament == null) return global;
  return inTournament.index > global.index ? inTournament : global;
}

/// Ob [role] Rollen [target] vergeben darf: Admin alles; Turnierleitung nur
/// Schreiber/Spieler/Zuschauer innerhalb ihres Turniers (nie Admin/Leitung).
bool canGrantRole(Role granter, Role target) {
  if (granter == Role.admin) return true;
  if (granter == Role.director) return target.index <= Role.scorer.index;
  return false;
}
