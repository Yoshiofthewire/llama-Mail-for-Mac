//
//  PushNotificationDispatcher.swift
//  llama Mail
//
//  UNUserNotificationCenter integration (spec §3, §5): category setup
//  (MAIL_NOTIFICATION, MFA_CHALLENGE with Approve/Deny), incoming payload
//  handling, local presentation for pull-mode arrivals, and routing taps to
//  NavigationActions for the UI layer (Phase 6 sets `onNavigate`).
//

import Foundation
import os
import UserNotifications

@MainActor
final class PushNotificationDispatcher: NSObject {
    static let mailCategoryId = "MAIL_NOTIFICATION"
    static let mfaCategoryId = "MFA_CHALLENGE"
    static let approveActionId = "APPROVE"
    static let denyActionId = "DENY"

    private let pushRepository: PushRepository
    private let approveMfaChallenge: ApproveMfaChallengeUseCase
    private let pushSettingsStore: PushSettingsStore

    /// Set by the UI layer to route notification taps.
    var onNavigate: ((NavigationAction) -> Void)?

    init(
        pushRepository: PushRepository,
        approveMfaChallenge: ApproveMfaChallengeUseCase,
        pushSettingsStore: PushSettingsStore
    ) {
        self.pushRepository = pushRepository
        self.approveMfaChallenge = approveMfaChallenge
        self.pushSettingsStore = pushSettingsStore
    }

    // MARK: - Setup

    /// Registers categories and takes over as the center's delegate.
    /// Call once at launch, before any notification can arrive.
    func configure(center: UNUserNotificationCenter = .current()) {
        center.delegate = self

        let mailCategory = UNNotificationCategory(
            identifier: Self.mailCategoryId,
            actions: [], // no direct actions; tap opens inbox (spec §3)
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let mfaCategory = UNNotificationCategory(
            identifier: Self.mfaCategoryId,
            actions: [
                UNNotificationAction(identifier: Self.approveActionId, title: "Approve", options: []),
                UNNotificationAction(identifier: Self.denyActionId, title: "Deny", options: [.destructive]),
            ],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([mailCategory, mfaCategory])
    }

    /// Spec §3: request at first app launch. Denial is fine — payloads are
    /// still parsed into in-app history.
    @discardableResult
    func requestAuthorization(center: UNUserNotificationCenter = .current()) async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    // MARK: - Incoming payloads

    /// Processes a remote payload (APNs wake or `xcrun simctl push`).
    func handleIncoming(userInfo: [AnyHashable: Any]) async {
        guard let payload = PushPayloadMapper.map(userInfo: userInfo) else {
            Log.push.warning("Ignoring unrecognized push payload")
            return
        }
        switch payload {
        case .mail(let mail):
            // APNs already showed the system banner (aps.alert); record history.
            do {
                try await pushRepository.recordPushArrival(mail)
            } catch {
                Log.push.error("Failed to record push arrival: \(error)")
            }
        case .mfaChallenge:
            // Alert + action buttons come from the aps payload's category;
            // nothing to persist (spec §5: don't retain challenge data).
            break
        }
    }

    /// Presents a local notification for a pull-mode arrival (the server
    /// never contacted APNs in pull mode, spec §3).
    func presentLocally(
        _ notification: PushNotification,
        center: UNUserNotificationCenter = .current()
    ) async {
        guard pushSettingsStore.systemNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = notification.senderName
        content.body = notification.emailSubject
        content.sound = .default
        content.categoryIdentifier = Self.mailCategoryId
        content.userInfo = [
            "messageId": notification.messageId,
            "senderName": notification.senderName,
            "emailSubject": notification.emailSubject,
            "Keywords": notification.keywords,
        ]
        let request = UNNotificationRequest(
            identifier: "pull-\(notification.seq)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            Log.push.error("Failed to present local notification: \(error)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationDispatcher: UNUserNotificationCenterDelegate {
    /// Foreground presentation: MFA challenges are high priority (banner +
    /// sound, spec §3); mail shows a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == Self.mfaCategoryId
            ? [.banner, .sound]
            : [.banner]
    }

    /// Action buttons and body taps.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case Self.approveActionId, Self.denyActionId:
            guard let challengeId = userInfo["challengeId"] as? String else { return }
            let approved = response.actionIdentifier == Self.approveActionId
            let outcome = await approveMfaChallenge(challengeId: challengeId, approved: approved)
            Log.push.info("MFA \(approved ? "approve" : "deny") outcome: \(String(describing: outcome))")

        case UNNotificationDefaultActionIdentifier:
            // Body tap: MFA → in-app approval fallback (spec §5); mail → inbox.
            switch PushPayloadMapper.map(userInfo: userInfo) {
            case .mfaChallenge(let challenge):
                onNavigate?(.openMfaApproval(challengeId: challenge.challengeId))
            case .mail(let mail):
                onNavigate?(.openEmail(messageId: mail.messageId))
            case nil:
                break
            }

        default:
            break
        }
    }
}
