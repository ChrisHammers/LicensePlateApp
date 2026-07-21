import { describe, it, expect } from "vitest";
import { buildFamilyInviteDisplaySnapshotFromData } from "./familyInviteDisplay";

describe("buildFamilyInviteDisplaySnapshotFromData", () => {
  it("builds family name, creator, inviter, and captains JSON", () => {
    const snapshot = buildFamilyInviteDisplaySnapshotFromData({
      familyName: "Roadtrippers",
      creatorId: "creator-1",
      fromUserId: "captain-1",
      usersById: {
        "creator-1": {
          userName: "ada",
          firstName: "Ada",
          lastName: "Creator",
          avatarId: "scout_otter",
        },
        "captain-1": {
          userName: "bob",
          firstName: "Bob",
          lastName: "Captain",
        },
      },
      captainMembers: [
        { userId: "creator-1", role: "creator" },
        { userId: "captain-1", role: "captain" },
      ],
    });

    expect(snapshot.familyName).toBe("Roadtrippers");
    expect(snapshot.creatorDisplayName).toBe("Ada Creator");
    expect(snapshot.creatorUserName).toBe("ada");
    expect(snapshot.creatorAvatarId).toBe("scout_otter");
    expect(snapshot.fromUserDisplayName).toBe("Bob Captain");
    expect(snapshot.fromUserUserName).toBe("bob");
    expect(snapshot.fromUserAvatarId).toBeNull();
    expect(snapshot.captainsPreview).toEqual([
      {
        displayName: "Ada Creator",
        userName: "ada",
        role: "creator",
        avatarId: "scout_otter",
        userId: "creator-1",
      },
      {
        displayName: "Bob Captain",
        userName: "bob",
        role: "captain",
        avatarId: null,
        userId: "captain-1",
      },
    ]);
    expect(JSON.parse(snapshot.captainsPreviewJSON)).toEqual(
      snapshot.captainsPreview
    );
  });

  it("includes creator when missing from members list", () => {
    const snapshot = buildFamilyInviteDisplaySnapshotFromData({
      familyName: "Solo",
      creatorId: "creator-1",
      fromUserId: "creator-1",
      usersById: {
        "creator-1": { userName: "solo", firstName: "Solo" },
      },
      captainMembers: [],
    });

    expect(snapshot.captainsPreview).toHaveLength(1);
    expect(snapshot.captainsPreview[0].role).toBe("creator");
    expect(snapshot.captainsPreview[0].userName).toBe("solo");
    expect(snapshot.captainsPreview[0].userId).toBe("creator-1");
  });
});
