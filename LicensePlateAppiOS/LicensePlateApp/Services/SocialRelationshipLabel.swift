//
//  SocialRelationshipLabel.swift
//  LicensePlateApp
//
//  Localized peer relationship labels for invite / friends surfaces.
//  Dual family+friend → "Friend & Family" (display); classification still Family-wins.
//

import Foundation

enum SocialRelationshipLabel {
    /// Visible + VoiceOver relationship string. Empty when neither family nor friend.
    static func localizedLabel(isFamily: Bool, isFriend: Bool) -> String {
        if isFamily && isFriend {
            return "Friend & Family".localized
        }
        if isFamily {
            return "Family".localized
        }
        if isFriend {
            return "Friend".localized
        }
        return ""
    }
}
