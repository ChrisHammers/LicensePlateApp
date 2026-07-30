/**
 * Pure authorization for removeFamilyMember (self-leave vs manager remove).
 */

export type FamilyMemberRemovalDecision =
  | { allowed: true }
  | { allowed: false; code: "permission-denied" | "failed-precondition"; message: string };

export function canRemoveFamilyMember(args: {
  actorRole: string;
  targetRole: string;
  isSelf: boolean;
}): FamilyMemberRemovalDecision {
  const { actorRole, targetRole, isSelf } = args;

  if (isSelf) {
    if (actorRole === "creator") {
      return {
        allowed: false,
        code: "failed-precondition",
        message: "Family creators must delete the family instead of leaving",
      };
    }
    return { allowed: true };
  }

  if (actorRole === "creator") {
    return { allowed: true };
  }

  if (actorRole === "captain") {
    if (targetRole === "captain") {
      return {
        allowed: false,
        code: "permission-denied",
        message: "Captains cannot remove other Captains",
      };
    }
    return { allowed: true };
  }

  return {
    allowed: false,
    code: "permission-denied",
    message: "Only Captains can remove members",
  };
}
