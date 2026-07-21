//
//  PushNotification.swift
//  KyPost
//
//  Domain model for a push notification history entry (spec §3, §8).
//  Payload keys are a binding contract with Android: messageId, senderName,
//  emailSubject, Keywords (capital K).
//

import Foundation

struct PushNotification: Identifiable, Hashable, Sendable {
    /// Strictly-increasing sequence number from the pull endpoint; used for de-duplication.
    var seq: Int
    var messageId: String
    var senderName: String
    var emailSubject: String
    var keywords: [String]
    var receivedAt: Date
    var read: Bool

    var id: Int { seq }
}
