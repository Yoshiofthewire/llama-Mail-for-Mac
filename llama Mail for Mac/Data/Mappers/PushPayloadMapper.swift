//
//  PushPayloadMapper.swift
//  llama Mail
//
//  Maps APNs userInfo dictionaries to domain payloads (spec §3, §5).
//  Binding contract with Android — exact keys: messageId, senderName,
//  emailSubject, Keywords (capital K); MFA: type == "mfa_challenge",
//  challengeId.
//

import Foundation

/// An email arrival announced via push; becomes a PushNotification history
/// entry once a seq is assigned (push mode has no server seq).
struct MailPushPayload: Equatable, Sendable {
    var messageId: String
    var senderName: String
    var emailSubject: String
    var keywords: [String]

    func toNotification(seq: Int, receivedAt: Date) -> PushNotification {
        PushNotification(
            seq: seq,
            messageId: messageId,
            senderName: senderName,
            emailSubject: emailSubject,
            keywords: keywords,
            receivedAt: receivedAt,
            read: false
        )
    }
}

enum PushPayload: Equatable, Sendable {
    case mail(MailPushPayload)
    case mfaChallenge(MfaChallenge)
}

enum PushPayloadMapper {
    /// Returns nil for payloads that are neither a mail arrival nor an MFA
    /// challenge (missing required keys).
    static func map(userInfo: [AnyHashable: Any], receivedAt: Date = Date()) -> PushPayload? {
        if userInfo["type"] as? String == MfaChallenge.payloadType {
            guard let challengeId = userInfo["challengeId"] as? String, !challengeId.isEmpty else {
                return nil
            }
            return .mfaChallenge(MfaChallenge(challengeId: challengeId, receivedAt: receivedAt))
        }

        guard let messageId = userInfo["messageId"] as? String, !messageId.isEmpty else {
            return nil
        }
        return .mail(MailPushPayload(
            messageId: messageId,
            senderName: userInfo["senderName"] as? String ?? "",
            emailSubject: userInfo["emailSubject"] as? String ?? "",
            keywords: userInfo["Keywords"] as? [String] ?? []
        ))
    }
}
