//
//  PushNotificationEntity.swift
//  KyPost
//
//  SwiftData entity for the push_notifications history table (spec §8).
//

import Foundation
import SwiftData

@Model
final class PushNotificationEntity {
    @Attribute(.unique) var seq: Int
    var messageId: String
    var senderName: String
    var emailSubject: String
    var keywords: [String]
    var receivedAt: Date
    var read: Bool

    init(
        seq: Int,
        messageId: String,
        senderName: String,
        emailSubject: String,
        keywords: [String],
        receivedAt: Date,
        read: Bool
    ) {
        self.seq = seq
        self.messageId = messageId
        self.senderName = senderName
        self.emailSubject = emailSubject
        self.keywords = keywords
        self.receivedAt = receivedAt
        self.read = read
    }
}

// MARK: - Mapping

extension PushNotificationEntity {
    convenience init(from notification: PushNotification) {
        self.init(
            seq: notification.seq,
            messageId: notification.messageId,
            senderName: notification.senderName,
            emailSubject: notification.emailSubject,
            keywords: notification.keywords,
            receivedAt: notification.receivedAt,
            read: notification.read
        )
    }

    var toDomain: PushNotification {
        PushNotification(
            seq: seq,
            messageId: messageId,
            senderName: senderName,
            emailSubject: emailSubject,
            keywords: keywords,
            receivedAt: receivedAt,
            read: read
        )
    }
}
